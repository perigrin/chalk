our $g = 1; sub f { local $g; defined $g ? "d" : "u" } print f(), $g, "\n";
