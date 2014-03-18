import bakthat
from bakthat.plugin import Plugin
from bakthat.backends import S3Backend

import os
import sys
import glob
import subprocess
import contextlib
import functools
import multiprocessing
import logging
import boto
from multiprocessing.pool import IMapIterator
import rfc822

log = logging.getLogger('bakthat')

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
  log.info("Transferring %s - %s", i, part)
  with open(part) as t_handle:
    mp.upload_part_from_file(t_handle, i+1)
  os.remove(part)

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

class MP_S3Backend(S3Backend):
  def __init__(self, conf={}, profile="default"):
    global conn
    S3Backend.__init__(self, conf, profile)
    conn = boto.connect_s3(self.conf["access_key"], self.conf["secret_key"])

  def upload(self, s3_keyname, transfer_file, **kwargs):
    log.info("Beginning monkey-patched upload!")
    use_rr = kwargs.get("s3_reduced_redundancy", False)
    cores = 4

    if self.conf["s3_prefix"]:
      s3_keyname = "%s/%s" % (self.conf["s3_prefix"], s3_keyname)

    mb_size = os.path.getsize(transfer_file) / 1e6
    if mb_size < 50:
      self._standard_transfer(self.bucket, s3_keyname, transfer_file, use_rr)
    else:
      self._multipart_upload(self.bucket, s3_keyname, transfer_file, mb_size, use_rr, cores)

  def upload_cb(self, complete, total):
    sys.stdout.write(".")
    sys.stdout.flush()

  def _standard_transfer(self, bucket, s3_key_name, transfer_file, use_rr):
    log.info("Upload with standard transfer, not multipart")
    new_s3_item = bucket.new_key(s3_key_name)
    new_s3_item.set_contents_from_filename(transfer_file, reduced_redundancy=use_rr,
                                           cb=self.upload_cb, num_cb=10)

  def _multipart_upload(self, bucket, s3_key_name, tarball, mb_size, use_rr=True, cores=None):
    """Upload large files using Amazon's multipart upload functionality.
    """
    log.info("Upload with multipart transfer")
    def split_file(in_file, mb_size, split_num=5):
      prefix = os.path.join(os.path.dirname(in_file),
                            "%sS3PART" % (os.path.basename(s3_key_name)))
      # require a split size between 5Mb (AWS minimum) and 500mb
      split_size = int(max(min(mb_size / (split_num * 2.0), 500), 5))
      if not os.path.exists("%saa" % prefix):
          cl = ["split", "-b%sm" % split_size, in_file, prefix]
          log.info("Splitting file")
          subprocess.check_call(cl)
      return sorted(glob.glob("%s*" % prefix))

    mp = bucket.initiate_multipart_upload(s3_key_name, reduced_redundancy=use_rr)
    with multimap(cores) as pmap:
        for _ in pmap(transfer_part, ((mp.id, mp.key_name, mp.bucket_name, i, part)
                                          for (i, part) in
                                          enumerate(split_file(tarball, mb_size, cores)))):
            pass
    mp.complete_upload()

class S3Swapper(Plugin):
  def activate(self):
    bakthat.STORAGE_BACKEND = dict(s3=MP_S3Backend)
    log.info('Replaced S3Backend with MP_S3Backend')
