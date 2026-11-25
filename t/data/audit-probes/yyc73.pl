my $x="a"; sub f { $x="z"; "b" } my $s = join ",", $x, f(); print "$s\n";
