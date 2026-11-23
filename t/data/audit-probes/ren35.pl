my %seen=(a=>1); my %work=%seen; while (my ($k)=sort keys %work) { delete $work{$k} } print scalar(keys %seen),"\n";
