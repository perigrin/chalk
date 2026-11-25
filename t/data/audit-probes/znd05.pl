my %h; $h{a}{b}++ for 1..3; push @{$h{$_ % 2}{l}},$_ for 1..4; print $h{a}{b}, scalar(@{$h{0}{l}}), "@{$h{1}{l}}\n";
