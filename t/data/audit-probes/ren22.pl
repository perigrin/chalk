my %h=(a=>1); my %c=%h; @c{qw(a b)}=(5,6); print join(",",map{"$_$h{$_}"}sort keys %h),"\n";
