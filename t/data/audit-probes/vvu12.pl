my $x = 1; my $c = sub :lvalue { $x }; sub f { $x = 7; $_[0] } print f($c->()), "\n";
