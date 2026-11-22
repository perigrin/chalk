my ($x, $y) = (1, 2); my $r = \$y; if (@ARGV) { ($x, $y) = (3, 4) } else { ($y, $x) = (5, 6) } print "$x $$r\n";
