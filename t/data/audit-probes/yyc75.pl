my $x="a"; sub f { $x="z"; "b" } print $x, f(), "\n";
