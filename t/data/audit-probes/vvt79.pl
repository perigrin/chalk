sub f { push @{$_[0]}, 1 } my $t = 0; for my $i (1..3) { my @y; f(\@y); f(\@y) if $i > 1; $t += @y } print "$t\n";
