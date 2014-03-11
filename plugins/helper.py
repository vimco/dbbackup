from bakthat.plugin import Plugin
from bakthat.helper import KeyValue

class MyKeyValue(KeyValue):
    def set_key(self, keyname, value, **kwargs):
        k = Key(self.bucket)
        k.key = keyname

        backup_date = int(time.time())
        backup = dict(filename=keyname,
                      stored_filename=keyname,
                      backup_date=backup_date,
                      last_updated=backup_date,
                      backend="s3",
                      is_deleted=False,
                      tags="",
                      metadata={"KeyValue": True,
                                "is_enc": False,
                                "is_gzipped": False})

        fileobj = StringIO(json.dumps(value))

        if kwargs.get("compress", True):
            backup["metadata"]["is_gzipped"] = True
            out = StringIO()
            f = GzipFile(fileobj=out, mode="w", compresslevel=0)
            f.write(fileobj.getvalue())
            f.close()
            fileobj = StringIO(out.getvalue())

        password = kwargs.get("password")
        if password:
            backup["metadata"]["is_enc"] = True
            out = StringIO()
            encrypt(fileobj, out, password)
            fileobj = out
        # Creating the object on S3
        k.set_contents_from_string(fileobj.getvalue())
        k.set_acl("private")
        backup["size"] = k.size

        access_key = self.conf.get("access_key")
        container_key = self.conf.get(self.container_key)
        backup["backend_hash"] = hashlib.sha512(access_key + container_key).hexdigest()
        Backups.upsert(**backup)

class ChangeModelPlugin(Plugin):
    def activate(self):
        global KeyValue
        self.log.info("Replace KeyValue with my non-compressing version")
        KeyValue = MyKeyValue
