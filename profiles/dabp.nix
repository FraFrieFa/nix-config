{ ... }:
{
  boot.kernelParams = [
    "nvme.poll_queues=4"
  ];
}
