my %h=(a=>1); %h = (b => $h{a}, c => scalar(keys %h)); print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";
