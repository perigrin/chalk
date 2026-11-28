our $/ = "\n"; { local $/ = undef; print defined $/ ? "d" : "u" } print defined $/ ? "d" : "u", "\n";
