import sys

matches : dict = {}
multis : list = []

def tokenize(line):
    wr_len = len("-wrapped")
    pkg = line.split(" ")[0]
    cmd = line.split("/")[-1].strip()
    if cmd[0] == '.' and cmd[-wr_len:] == "-wrapped":
        return None
    elif pkg[0] == '(' and pkg[-1] == ')':
        return None
    else:
        return cmd, pkg

while True:
    line = sys.stdin.readline()
    if not line:
        break
    upd = tokenize(line)
    if upd:
        cmd, pkg = upd
        if cmd in multis:
            continue
        elif cmd in matches.keys():
            matches.pop(cmd)
            multis.append(cmd)
            print(f"{cmd}\t(from multiple sources)")
        else:
            matches.update({cmd: pkg})

for cmd, pkg in matches.items():
    print(f"{cmd}\t(from {pkg})")
