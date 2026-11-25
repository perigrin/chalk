our $g="ab"; sub t { $g =~ tr/a/z/ } sub f { "@_" } print f($g, t()), "\n";
