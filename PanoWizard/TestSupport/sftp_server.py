# Local integration fixture only. Install Paramiko in a separate Python venv.
# Run this server, then enable PANOWIZARD_SFTP_TEST=1 in the Xcode scheme's
# Test environment and run SFTPPublisherTests. No real account is used.
import os, socket, threading, tempfile, paramiko
from pathlib import Path
temporary = tempfile.TemporaryDirectory(prefix='panowizard-sftp-test-')
root = Path(temporary.name).resolve()
(root/'base').mkdir()
(root/'outside').mkdir()
(root/'base'/'not-a-directory').write_text('existing file')
(root/'base'/'escape').symlink_to(root/'outside', target_is_directory=True)
key = paramiko.ECDSAKey.generate()
class Auth(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if (username,password)==('publisher','test-password') else paramiko.AUTH_FAILED
    def get_allowed_auths(self, username): return 'password'
    def check_channel_request(self, kind, chanid): return paramiko.OPEN_SUCCEEDED if kind=='session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
class Files(paramiko.SFTPServerInterface):
    def local(self,p):
        return root / p.lstrip('/')
    def canonicalize(self,p):
        relative = self.local(p).resolve().relative_to(root).as_posix()
        return '/' if relative == '.' else '/' + relative
    def mkdir(self,p,attr):
        if 'denied' in Path(p).parts: return paramiko.SFTP_PERMISSION_DENIED
        try: self.local(p).mkdir(); return paramiko.SFTP_OK
        except OSError as e: return paramiko.SFTPServer.convert_errno(e.errno)
    def stat(self,p):
        try: return paramiko.SFTPAttributes.from_stat(self.local(p).stat())
        except OSError as e: return paramiko.SFTPServer.convert_errno(e.errno)
    def open(self,p,flags,attr):
        try:
            fd=os.open(self.local(p),flags,0o644)
            f=os.fdopen(fd,'wb' if flags & os.O_WRONLY else 'rb')
            h=paramiko.SFTPHandle(flags)
            if flags & os.O_WRONLY: h.writefile=f
            else: h.readfile=f
            return h
        except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno)
sock=socket.socket();sock.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);sock.bind(('127.0.0.1',22229));sock.listen(10)
def serve(conn):
    t=paramiko.Transport(conn);t.add_server_key(key);t.set_subsystem_handler('sftp',paramiko.SFTPServer,Files)
    try:
        t.start_server(server=Auth())
        while t.is_active(): threading.Event().wait(.1)
    finally:t.close()
print('ready',flush=True)
while True:
    conn,_=sock.accept();threading.Thread(target=serve,args=(conn,),daemon=True).start()
