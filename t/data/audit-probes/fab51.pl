my %h; $h{a} ||= []; push @{$h{a}}, 1; $h{a} ||= [9]; print scalar(@{$h{a}}),"\n";
