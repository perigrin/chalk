our $g = 5; sub dec { --$g } my $n = 0; $n++ while dec() > 0; print "$n$g\n";
