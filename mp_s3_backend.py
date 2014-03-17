from bakthat.plugin import Plugin
import bakthat.backends

import os
import sys
import glob
import subprocess
import contextlib
import functools
import multiprocessing
from multiprocessing.pool import IMapIterator
from optparse import OptionParser
import rfc822


class MP_S3Backend(bakthat.backends.S3Backend):
  def upload(self, s3_keyname, transfer_file, **kwargs):
    self.log.info("Beginning monkey-patched upload!")
    use_rr = kwargs.get("s3_reduced_redundancy", False)
    cores = 4

    mb_size = os.path.getsize(transfer_file) / 1e6
    if mb_size < 50:
        _standard_transfer(bucket, s3_key_name, transfer_file, use_rr)
    else:
        _multipart_upload(bucket, s3_key_name, transfer_file, mb_size, use_rr, cores)

  def s3_has_uptodate_file(bucket, transfer_file, s3_key_name):
      """Check if S3 has an existing, up to date version of this file.
      """
      s3_key = bucket.get_key(s3_key_name)
      if s3_key:
          s3_size = s3_key.size
          local_size = os.path.getsize(transfer_file)
          s3_time = rfc822.mktime_tz(rfc822.parsedate_tz(s3_key.last_modified))
          local_time = os.path.getmtime(transfer_file)
          return s3_size == local_size and s3_time >= local_time
      return False

  def upload_cb(complete, total):
      sys.stdout.write(".")
      sys.stdout.flush()

  def _standard_transfer(bucket, s3_key_name, transfer_file, use_rr):
      self.log.info("Upload with standard transfer, not multipart")
      new_s3_item = bucket.new_key(s3_key_name)
      new_s3_item.set_contents_from_filename(transfer_file, reduced_redundancy=use_rr,
                                             cb=upload_cb, num_cb=10)

  def map_wrap(f):
      @functools.wraps(f)
      def wrapper(*args, **kwargs):
          return apply(f, *args, **kwargs)
      return wrapper

  def mp_from_ids(mp_id, mp_keyname, mp_bucketname):
      """Get the multipart upload from the bucket and multipart IDs.

      This allows us to reconstitute a connection to the upload
      from within multiprocessing functions.
      """
      conn = boto.connect_s3()
      bucket = conn.lookup(mp_bucketname)
      mp = boto.s3.multipart.MultiPartUpload(bucket)
      mp.key_name = mp_keyname
      mp.id = mp_id
      return mp

  @map_wrap
  def transfer_part(mp_id, mp_keyname, mp_bucketname, i, part):
      """Transfer a part of a multipart upload. Designed to be run in parallel.
      """
      mp = mp_from_ids(mp_id, mp_keyname, mp_bucketname)
      self.log.info("Transferring", i, part)
      with open(part) as t_handle:
          mp.upload_part_from_file(t_handle, i+1)
      os.remove(part)

  def _multipart_upload(bucket, s3_key_name, tarball, mb_size, use_rr=True,
                        cores=None):
      """Upload large files using Amazon's multipart upload functionality.
      """
      self.log.info("Upload with multipart transfer")
      def split_file(in_file, mb_size, split_num=5):
          prefix = os.path.join(os.path.dirname(in_file),
                                "%sS3PART" % (os.path.basename(s3_key_name)))
          # require a split size between 5Mb (AWS minimum) and 250Mb
          split_size = int(max(min(mb_size / (split_num * 2.0), 250), 5))
          if not os.path.exists("%saa" % prefix):
              cl = ["split", "-b%sm" % split_size, in_file, prefix]
              subprocess.check_call(cl)
          return sorted(glob.glob("%s*" % prefix))

      mp = bucket.initiate_multipart_upload(s3_key_name, reduced_redundancy=use_rr)
      with multimap(cores) as pmap:
          for _ in pmap(transfer_part, ((mp.id, mp.key_name, mp.bucket_name, i, part)
                                        for (i, part) in
                                        enumerate(split_file(tarball, mb_size, cores)))):
              pass
      mp.complete_upload()

  @contextlib.contextmanager
  def multimap(cores=None):
      """Provide multiprocessing imap like function.

      The context manager handles setting up the pool, worked around interrupt issues
      and terminating the pool on completion.
      """
      if cores is None:
          cores = max(multiprocessing.cpu_count() - 1, 1)
      def wrapper(func):
          def wrap(self, timeout=None):
              return func(self, timeout=timeout if timeout is not None else 1e100)
          return wrap
      IMapIterator.next = wrapper(IMapIterator.next)
      pool = multiprocessing.Pool(cores)
      yield pool.imap
      pool.terminate()

class S3Swapper(Plugin):
  def activate(self):
    self.log.info('Replacing S3Backend with MP_S3Backend')
    bakthat.backends.S3Backend = MP_S3Backend
