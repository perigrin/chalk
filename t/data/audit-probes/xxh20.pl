sub f { my ($p) = @_; $p } my %d = (f => \&f); my $x = 1; my @l = ($d{f}->($x), $x = 2, $d{f}->($x)); print "@l\n";
