my %h=(a=>1); my %c=%h; my %d=%c; %c=(); print join(",",keys %d), scalar(keys %h), "\n";
