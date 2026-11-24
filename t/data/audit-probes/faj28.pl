my %h; my @v=map { $_ } @h{qw(a)}; my @g=grep { 1 } $h{b}; print scalar(keys %h),"\n";
