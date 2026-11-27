our $g = 1; sub rd { $g } my $v = eval { local $g = 2; rd() } + rd(); print "$v\n";
