my %h=(a=>1,b=>2); my %c=%h; $c{a}=9; print join(",",map{"$_$h{$_}"}sort keys %h),"\n";
