our $g = 1; my $v = do { local $g = 2; $g }; print "$g $v\n";
