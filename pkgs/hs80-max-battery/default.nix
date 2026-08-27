{ lib, python3Packages }:

python3Packages.buildPythonApplication {
  pname = "hs80-max-battery";
  version = "0.1.0";
  pyproject = true;

  src = ./.;
  build-system = [ python3Packages.setuptools ];
  dependencies = [ python3Packages.pyside6 ];

  pythonImportsCheck = [ "hs80_max_battery" "hs80_max_tray" ];

  meta = {
    description = "Passive battery report monitor for the Corsair HS80 MAX receiver";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hs80-max-battery";
  };
}
