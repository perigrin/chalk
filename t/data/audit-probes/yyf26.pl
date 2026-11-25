sub f {} my %h; f(@h{qw(a b)}); print scalar(keys %h), "\n";
