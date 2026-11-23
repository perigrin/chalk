my %h=(a=>1); %h=(%h,b=>2); print join(",",sort keys %h),"\n";
