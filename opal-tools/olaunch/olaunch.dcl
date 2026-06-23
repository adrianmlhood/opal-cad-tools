// Opal CAD Tools launcher -- main-toolbox variants picked by mode:
//   opal_launcher           teammate / bundle build (Standardize only; no dev actions)
//   opal_launcher_dev       dev build (adds Advanced >, Reload, Switch to Bundle)
//   opal_launcher_prodtest  prod-test preview (adds Back to DEV; NOT shipped to real users)
//   opal_advanced           dev-only submenu off the toolbox: Save Layers/Filters (drawing -> master)
// The launcher LISP picks the main variant from _olaunch-mode (DEV when loading from source).

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
      label = "Spacing";
      : button { key = "OMODSPACE"; label = "One Array"; }
      : button { key = "OPVSPACE"; label = "All Arrays"; }
    }
    : boxed_column {
      label = "Select";
      : button { key = "QQA"; label = "One Array"; }
      : button { key = "SSA"; label = "All Arrays"; }
    }
    : boxed_column {
      label = "Layers";
      : button { key = "LKAPPLY"; label = "Standardize"; }
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
      label = "Spacing";
      : button { key = "OMODSPACE"; label = "One Array"; }
      : button { key = "OPVSPACE"; label = "All Arrays"; }
    }
    : boxed_column {
      label = "Select";
      : button { key = "QQA"; label = "One Array"; }
      : button { key = "SSA"; label = "All Arrays"; }
    }
    : boxed_column {
      label = "Layers";
      : button { key = "LKAPPLY"; label = "Standardize"; }
      : button { key = "ADV";     label = "Advanced >"; }
    }
    : boxed_column {
      label = "Setup";
      : button { key = "MODESW"; label = "Switch to Bundle"; }
      : button { key = "OHELP";  label = "Help"; }
    }
  }
  spacer;
  : button { key = "cancel"; label = "Close"; is_cancel = true; is_default = true; }
}

opal_launcher_prodtest : dialog {
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
      label = "Spacing";
      : button { key = "OMODSPACE"; label = "One Array"; }
      : button { key = "OPVSPACE"; label = "All Arrays"; }
    }
    : boxed_column {
      label = "Select";
      : button { key = "QQA"; label = "One Array"; }
      : button { key = "SSA"; label = "All Arrays"; }
    }
    : boxed_column {
      label = "Layers";
      : button { key = "LKAPPLY"; label = "Standardize"; }
    }
    : boxed_column {
      label = "Setup";
      : button { key = "MODEDEV"; label = "Back to DEV"; }
      : button { key = "OHELP";   label = "Help"; }
    }
  }
  spacer;
  : button { key = "cancel"; label = "Close"; is_cancel = true; is_default = true; }
}

// Dev-only submenu off the toolbox. < Back returns to the main toolbox.
opal_advanced : dialog {
  label = "Advanced";
  : text { label = "Push THIS drawing up to the shared master (careful):"; }
  spacer;
  : button { key = "LKSAVE"; label = "Save Layers/Filters -> master"; }
  spacer;
  : button { key = "back"; label = "< Back"; is_cancel = true; }
}
