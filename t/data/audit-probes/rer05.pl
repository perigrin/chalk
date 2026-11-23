my @d=(1,2); my %h=(a=>\@d); my %c=%h; $c{b}=1; print join(",",sort keys %h),"\n";
