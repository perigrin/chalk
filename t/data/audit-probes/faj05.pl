my %h=(a=>1); for ($h{a}, $h{b}) { $_ //= 0; $_++ } print join(",",map{"$_$h{$_}"}sort keys %h),"\n";
