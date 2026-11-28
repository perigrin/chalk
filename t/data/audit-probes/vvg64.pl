my @s = (); push @s, [$_, $_ * 2] for 1..3; my $t = 0; $t += $_->[1] for @s; print "$t\n";
