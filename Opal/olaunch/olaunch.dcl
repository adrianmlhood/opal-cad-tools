opal_launcher : dialog {
  label = "Opal CAD Tools";
  : row {
    : image {
      key = "logo";
      width = 16;
      height = 6;
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
      : button { key = "ODC";       label = "DC String"; }
      : button { key = "ORESPACE";  label = "Respace Rows"; }
    }
    : boxed_column {
      label = "Layers";
      : button { key = "LKAPPLY";   label = "Clean Up + Apply"; }
      : button { key = "LKCLEANUP"; label = "Clean Up Layers"; }
      : button { key = "LKBYLAYER"; label = "Force ByLayer"; }
      : button { key = "LKSTD";     label = "Layer Standards"; }
      : button { key = "LKFILTER";  label = "Layer Filters"; }
    }
    : boxed_column {
      label = "Setup";
      : button { key = "OSET";   label = "Calibrate"; }
      : button { key = "OLOAD";  label = "Reload Tools"; }
      : button { key = "OHELP";  label = "Help"; }
    }
  }
  spacer;
  : button {
    key = "cancel";
    label = "Close";
    is_cancel = true;
    is_default = true;
  }
}
