sub inc { $_[0]++ } my %h; inc($h{new}); inc($h{a}{b}); print "$h{new}$h{a}{b}\n";
