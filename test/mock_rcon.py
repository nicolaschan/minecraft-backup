# Reference: https://docs.python.org/3/library/socketserver.html
import codecs
import socketserver
import sys

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        while True:
            length = int.from_bytes(self.request.recv(4), 'little')
            if not length:
                continue

            self.request.recv(4)
            type_ = int.from_bytes(self.request.recv(4), 'little')
            self.data = self.request.recv(length - 8)[:-2].decode('utf-8')
            if self.data:
                if type_ == 2:
                    print(self.data)
                    sys.stdout.flush()
            try:
                if type_ == 3 and self.data != sys.argv[2]:
                    self.request.sendall(codecs.decode('0a000000ffffffff020000000000', 'hex'))
                else:
                    self.request.sendall(codecs.decode('0a00000010000000020000000000', 'hex'))
            except:
                break

if __name__ == "__main__":
    HOST, PORT = "localhost", int(sys.argv[1])
    with socketserver.ThreadingTCPServer((HOST, PORT), Handler) as server:
        server.serve_forever()
