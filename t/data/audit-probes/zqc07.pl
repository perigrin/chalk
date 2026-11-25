my %h=(a=>1); sub z { $h{a}=7 } for my $v ($h{a}) { z(); print $v } print "\n";
