my %h=(a=>1); my %c=%h; $c{a}||=7; $c{z}//=1; print join(",",sort keys %h),"\n";
