our $g=1; sub t { local $g; defined $g ? "d" : "u" } print t(), $g, "\n";
