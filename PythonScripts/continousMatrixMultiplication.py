import torch
import time

x = torch.rand(15000, 15000).cuda()
y = torch.rand(15000, 15000).cuda()

iters = 0
start = time.time()

while True:
    z = torch.matmul(x, y)
    iters += 1
    elapsed = time.time() - start
    if iters % 10 == 0:
        print(f"Iters: {iters}, Elapsed: {elapsed:.2f}s")

