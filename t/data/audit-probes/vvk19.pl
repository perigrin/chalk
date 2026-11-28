sub f { wantarray } my @l = f(); my $s = f(); f(); print $l[0], $s, "\n";
