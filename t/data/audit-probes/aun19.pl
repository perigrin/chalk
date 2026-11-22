our $g = 0; sub bump { $g += 10 } my $i = 0; { $g = $g + 1; bump(); redo if ++$i < 3 } print "$g\n";
