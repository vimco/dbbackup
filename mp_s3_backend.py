from bakthat.plugin import Plugin
from bakthat.backends import S3Backend

class MP_S3Backend(S3Backend)
  def upload(self, keyname, filename, **kwargs)
    k = Key(self.bucket)
    upload_kwargs = {"reduced_redundancy": kwargs.get("s3_reduced_redundancy", False)}
    if kwargs.get("cb", True):
      upload_kwargs = dict(cb=self.cb, num_cb=10)
    mp = self.bucket.initiate_multipart_upload(keyname, **upload_kwargs)
    with multimap(cores) as pmap:
      for _ in pmap(transfer_part, ((mp.id, mp.key_name, mp.bucket_name, i, part)
                                    for (i, part) in
                                    enumerate(split_file(filename, mb_size, cores)))):
          pass
    mp.complete_upload()

  def split_file(in_file, mb_size, split_num=5):
      prefix = os.path.join(os.path.dirname(in_file),
                            "%sS3PART" % (os.path.basename(s3_key_name)))
      split_size = int(min(mb_size / (split_num * 2.0), 250))
      if not os.path.exists("%saa" % prefix):
        cl = ["split", "-b%sm" % split_size, in_file, prefix]
        subprocess.check_call(cl)
      return sorted(glob.glob("%s*" % prefix))

  @contextlib.contextmanager
  def multimap(cores=None):
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

  def mp_from_ids(mp_id, mp_keyname, mp_bucketname):
      conn = boto.connect_s3()
      bucket = conn.lookup(mp_bucketname)
      mp = boto.s3.multipart.MultiPartUpload(bucket)
      mp.key_name = mp_keyname
      mp.id = mp_id
      return mp

  @map_wrap
  def transfer_part(mp_id, mp_keyname, mp_bucketname, i, part):
      mp = mp_from_ids(mp_id, mp_keyname, mp_bucketname)
      print " Transferring", i, part
      with open(part) as t_handle:
          mp.upload_part_from_file(t_handle, i+1)
      os.remove(part)


class S3Swapper(Plugin)
  def activate(self)
    global S3Backend
    self.log.info('Replacing S3Backend with MP_S3Backend')
    S3Backend = MP_S3Backend

