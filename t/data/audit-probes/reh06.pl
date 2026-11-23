my %h=(a=>1,b=>2); %h=(reverse %h); print join(",",map{"$_$h{$_}"}sort keys %h),"\n";
