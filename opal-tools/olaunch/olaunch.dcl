// Opal CAD Tools launcher -- two main-toolbox variants:
//   opal_launcher      teammate / bundle build (no Reload Tools)
//   opal_launcher_dev  dev build (adds Reload Tools)
// The launcher LISP picks one by mode (DEV when loading from the source tree).

opal_launcher : dialog {
  label = "Opal CAD Tools";
  : row {
    : image {
      key = "logo";
      width = 10;
      height = 6;
      aspect_ratio = 1;
      color = -15;
    }
    : column {
      : text { label = "OPAL CAD TOOLS"; }
      : text { key = "ver"; label = "v1.0"; }
      : text { label = "AutoCAD design tools"; }
    }
  }
  spacer;
  : row {
    : boxed_column {
      label = "Draw";
      : button { key = "ORESPACE"; label = "Respace Rows"; }
    }
    : boxed_column {
      label = "Layers";
      : button { key = "LAYERS"; label = "Layer Tools >"; }
    }
    : boxed_column {
      label = "Setup";
      : button { key = "OHELP";  label = "Help"; }
    }
  }
  spacer;
  : button { key = "cancel"; label = "Close"; is_cancel = true; is_default = true; }
}

opal_launcher_dev : dialog {
  label = "Opal CAD Tools";
  : row {
    : image {
      key = "logo";
      width = 10;
      height = 6;
      aspect_ratio = 1;
      color = -15;
    }
    : column {
      : text { label = "OPAL CAD TOOLS"; }
      : text { key = "ver"; label = "v1.0"; }
      : text { label = "AutoCAD design tools"; }
    }
  }
  spacer;
  : row {
    : boxed_column {
      label = "Draw";
      : button { key = "ORESPACE"; label = "Respace Rows"; }
    }
    : boxed_column {
      label = "Layers";
      : button { key = "LAYERS"; label = "Layer Tools >"; }
    }
    : boxed_column {
      label = "Setup";
      : button { key = "OLOAD";  label = "Reload Tools"; }
      : button { key = "MODESW"; label = "Switch to Bundle"; }
      : button { key = "OHELP";  label = "Help"; }
    }
  }
  spacer;
  : button { key = "cancel"; label = "Close"; is_cancel = true; is_default = true; }
}

opal_layers : dialog {
  label = "Layer Tools";
  : text { label = "Choose an action:"; }
  spacer;
  : button { key = "LKAPPLY";  label = "Clean up + standardize (all)"; }
  : button { key = "STDSAVE";  label = "Save current layers as the standard"; }
  : button { key = "STDSET";   label = "Apply the standard to this drawing"; }
  : button { key = "FILBUILD"; label = "Build filter groups from the standard"; }
  : button { key = "FILSAVE";  label = "Save the current filter groups"; }
  spacer;
  : button { key = "back"; label = "< Back"; is_cancel = true; }
}
