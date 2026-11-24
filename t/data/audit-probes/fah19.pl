our $x=1; sub f { $x=2; if ($_[0] == 2) { return "new" } "old" } print f($x),"\n";
