sub as { my ($x, $y); ($x, $y) = @_ } my $s = as(5, 6, 7); my @l = as(5, 6, 7); $l[0]++; print "$s|@l\n";
