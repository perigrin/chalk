my %h=(a=>1); my %c=%h; %h=%c; $h{a}=7; print "$c{a}\n";
