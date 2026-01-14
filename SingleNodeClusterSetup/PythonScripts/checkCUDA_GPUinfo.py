import torch

if torch.cuda.is_available():
    print("CUDA is available")
    print("GPU Name:", torch.cuda.get_device_name(0))
    print("Number of GPUs:", torch.cuda.device_count())

else:
    print("CUDA is not available")
