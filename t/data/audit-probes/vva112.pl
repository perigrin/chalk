our $/ = "\n"; { local $/; print defined $/ ? "d" : "u" } print defined $/ ? "d" : "u", "\n";
