our $e=0; sub d { die "boom\n" } eval { $e=1; d(); $e=2 }; print "$e $@";
