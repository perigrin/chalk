our $g = "o"; sub f { local $g = "i"; die { v => $g } } eval { f() }; print $@->{v}, $g, "\n";
