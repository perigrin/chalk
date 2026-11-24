my %h=(a=>1); %h=(%h,b=>2); print join(",",map {"$_=$h{$_}"} sort keys %h),"\n";
