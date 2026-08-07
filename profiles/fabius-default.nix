{ ... }:
{
  local.primaryUser = {
    name = "fabius";
    description = "Fabius";
  };

  users.users.root.hashedPassword = "!";
}
