my $cnt = 0; sub tick { ++$cnt } my @l = (tick(), tick(), $cnt); print "@l\n";
