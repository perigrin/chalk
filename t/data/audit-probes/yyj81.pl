my $c = \&f; sub f { "f@_" } my $d = \&$c; my %t = (k => $c); print $c->(1), &$c(2), &{$d}(3), $t{k}->(4), ref($c), "\n";
