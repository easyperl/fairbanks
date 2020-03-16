#!/usr/bin/perl

use strict;
use warnings;

# Author: Michael (Mike) Giles <mike@michaelsgiles.com>
# 
# Summary:
#   I saw this more as a test of data sanity checks and handling of 
#      unexpected cases with the data, instead of just whether an algorithm
#      could be created that most could google a solution to quickly enough.
#      Also some syntax could have been written differently based on coding
#      style already used at the customer's site.  I tend to err on the side
#      of being more legible than using Perl tricks to save lines/characters. 
#
# Usage (run script without args for syntax and example datafile contents):
#   ./<scriptname>.pl <data_filename>
#
# Input file example (remove leading hash and spaces):
#   $15.05
#   mixed fruit,$2.15
#   unmixed fruit,$2.15
#   french fries,$2.75
#   side salad,$3.35
#   hot wings,$3.55
#   mozzarella sticks,$4.20
#   sampler plate,$5.80
#
# Output:
#   Unquoted csv style list of dishes per line that total the target price.
#   For different dishes at same price a pipe delimeter "|" is used as an
#     parsable "or" between the possible dish options in the solution line.
#
# Internal Options:
#   $VERBOSE - set to 1 for iteration notices
#   $SILENT_ERRORS - set to 1 to stop data file issue reporting
#
# Assumptions made:
#   Quantity of any dish not limited to one per solution
#   Data file may contain multple sets of total/dish entries
#   Data file empty lines are ignored
#   Data file must follow example line order
#   Multiple dishes may be same price and interchangable/additive (this adds
#      logic/code in the output_solutions sub that would be unneeded
#      if we did not make this assumption)
#
# Checks made:
#   No execution argument results in Usage
#   File can be read
#   Bad data file lines are called out (with line number) and ignored:
#      Prices not conforming to standard currency format
#      Target price without trailing dishes found before another target price
#      Target price ending file without trailing dishes (edge case)
#   Dishes found before target price causes ignoring of dishes until target found
#   There is at least 1 valid solution (notify if not, per requirements)

# Flags that may need to be set/unset if output not being read by human.
# SILENT_ERRORS being turned on will mask data issues, so each output line
#   contains a "<datafile> ERROR:" string that can be caught by caller
#   automation/regex for sanity.
my $VERBOSE = 1; # just extra output (not good if results read by script)
my $SILENT_ERRORS = 0; # show/stop all error output relating to data issues

Main(@ARGV);
exit;

sub Main {
    my ($inputfile) = shift;
    my $linenum = 0; # for output during data file errors
    my $pricetarget; # target price to spend
    my @dish_prices; # array of found prices
    my %dish_lookup; # lookup hash (of array in case multiple dishes are same 
                     # price) to translate prices to dish name
    my $found_dishes = 0; # keep track of being in a dishes data section
    my $found_pricetarget = 0; # keep track of having found a price target

    if (!$inputfile) {
	usage();
	exit;
    }
    open (INPUTFH, '<', $inputfile) or die "Invalid file at $inputfile (check permissions and existance), exiting...";
    # loop will handle multiple total/dish entries in a single file
    while (my $line = <INPUTFH>) {
	
	chomp $line;
	$linenum++;

	# handle inputfile issues
	next if $line =~ /^\s*$/; # ignore blank lines
	if ($line !~ /^\$\d+\.[\d]{2}$|^.+\,\$\d+\.[\d]{2}$/) {
	    # line has unexpected garbage, alert and ignore
	    print "$inputfile($linenum) ERROR: unexpected data found, ignored - $line\n" unless $SILENT_ERRORS;
	    next;
	}

	# process valid lines into target price or dishes
	if ($line =~ /^\$(\d+\.[\d]{2})$/) {
	    # if a price target existed prior without dishes trailing, error
	    if ($found_pricetarget && ! $found_dishes) {
		print "$inputfile(?) ERROR: price target found without dishes, ignored - $pricetarget\n" unless $SILENT_ERRORS;
	    }
	    # if this is a new price target but we have been collecting dishes
	    if ($found_pricetarget && $found_dishes) {
		# we already have a set of target/dishes, process them first
		print "$inputfile: processing data set combination in file\n" if $VERBOSE;

		# get list of dish prices that will work
		my @solutions = Solve($pricetarget,\@dish_prices);
		# output the names of the dishes
		output_solutions(\@solutions,\%dish_lookup);
		
		# clear data for new target price iteration
		%dish_lookup = ();
		@dish_prices = ();
		$found_dishes = 0;
	    }
	    # price total line, store it, ignoring currency symbol
	    $pricetarget = $1;
	    $pricetarget =~ s/\.//; # get rid of decimal to stop floating point math issues (everything is in cents now)
	    # note that we found a price target
	    $found_pricetarget++;
	    next;
	}
	if ($line =~ /^(.+)\,\$(\d+\.[\d]{2})$/) { # found dish line
	    if (! $found_pricetarget) { # found dishes out of order, skip
		print "$inputfile($linenum) ERROR: found dishes before target price, ignoring - $line\n" unless $SILENT_ERRORS;
		next;
	    }
	    # store dish/price in lookup hash and store price to test
	    my $dish_name = $1;
	    my $int_price = $2;
	    $int_price =~ s/\.//; # get rid of decimal to stop floating point math issues (everything is in cents now)
	    push @{ $dish_lookup{$int_price} }, $dish_name;
	    push @dish_prices, $int_price;
	    $found_dishes++;
	    next;
	}
	print "$inputfile($linenum) ERROR: you should not see this error, contact author and and copy/paste this entire error message: $line\n" unless $SILENT_ERRORS;
    }
    if ($found_pricetarget && ! $found_dishes) {
	# edge case of price target ending file with no dishes after
	print "$inputfile ERROR: found target price at end of file with no dishes, ignoring\n" unless $SILENT_ERRORS;
    }
    
    if ($found_pricetarget && $found_dishes) {
	# we have a target price and at least one dish at the end of the file
	print "$inputfile: process final/only data set combination in file\n" if $VERBOSE;
	my @solutions = Solve($pricetarget,\@dish_prices);
	output_solutions(\@solutions,\%dish_lookup);
    }
    
    close (INPUTFH);
    return 1;
}

#
# Sub looks through array of solution arrays containing prices that worked
#   then looks up the dish names based on prices and constructs the csv
#   style output of one solution per line
#
sub output_solutions {
    my $solutions_ref = shift;
    my $dish_lookup_ref = shift;
    my @solutions = @$solutions_ref;
    my %dish_lookup = %$dish_lookup_ref;
    my $solution_count = 0; # keep track if we found solutions and how many
    my %uniq_solutions_by_name; # required for options at the same price
    foreach my $solution ( @solutions ) {
	my @solutions_by_name;
	$solution_count++;
	foreach my $price ( @{$solution} ) {
	    # lookup via hash of arrays what dishes are this price
	    my $dishes_ref = $dish_lookup{$price};
	    if (@$dishes_ref >= 2) { # more than one dish at the price
		my $temp = join '|', @$dishes_ref;
		push @solutions_by_name, $temp;
	    } else { # only one dish at the price
		push @solutions_by_name, @$dishes_ref[0];
	    }
	}

	my $solutions_hash_key = join (',',@solutions_by_name);
	$uniq_solutions_by_name{$solutions_hash_key} = 1;
    }

    # this was done for when multiple products are the same price, they will
    # be presented with a | between them signifying either dish could be used
    # to meet the criteria.  Since the solution is possible with either,
    # technically there would be identical solutions... so this handles that.
    # Another option would be to code it to iterate through the options per
    # line but that would add more code and can be done later if desired.
    ####  quick example  ####
    #    A and B are same price... solution currently is:
    # A|B,C,D
    #    as opposed to:
    # A,C,D
    # B,C,D
    #
    # Although, now that the system handles repeats of the same product, this
    # would be far more involved.
    foreach (sort keys %uniq_solutions_by_name) { # remove sort if not desired or for extremely large data set
	print $_ . "\n";
    }
    
    if ( !$solution_count) {
	print "There is no combination of dishes that will be equal in cost to the target price.\n";
    }

     print "solutions found - $solution_count\n" if $VERBOSE;

    return 1;
}

#
# Show really basic usage
#
sub usage {
    print "Usage:\n";
    print "\t$0 <datafile>\n";
    my $example_data = q{
$15.05
mixed fruit,$2.15
unmixed fruit,$2.15
french fries,$2.75
side salad,$3.35
hot wings,$3.55
mozzarella sticks,$4.20
sampler plate,$5.80

};
    print "\nExample datafile contents:\n";
    print $example_data ;
    return;
}

#
# Calculates solutions for our dish / total challenge
#
sub subSums {
    # values = array of possibles prices and count for this match
    # prices = which of @values array indicies contain a non-zero count
    my ($results_aref, $values_aref, $remaining, $index) = @_;
    my @values = @$values_aref;

    return if $remaining <= 0;

    my $value = $values[$index][0];
    my $counter = \$values[$index][1];
    
    if ($index == $#values) {
	
        #Special case for last element
        $$counter = int ($remaining / $value);
        buildResult ($index,$results_aref,$values_aref) if $value * $$counter == $remaining;
        return;
    }

    while ($remaining >= $value * $$counter) {
        buildResult ($index,$results_aref,$values_aref), last if $value * $$counter == $remaining;
        subSums ($results_aref, $values_aref, $remaining - $value * $$counter, $index + 1);
        ++$$counter;
    }
    $$counter = 0; # Reset counter
}

#
# Builds array of solution arrays, created by subSums
#
sub buildResult {
    # values = array of possibles prices and count for this match
    # prices = which of @values array indicies contain a non-zero count
    my $index = shift;
    my $results = shift;
    my $values_aref = shift;

    my @prices = grep {$values_aref->[$_][1]} (0..$index);

    my @result_strings = ();
    foreach my $price (@prices) {
        my $line;
        my @multiples;
        for (my $i=0;$i < $values_aref->[$price][1]; $i++) {
            push @multiples, $values_aref->[$price][0];
        }
	push (@result_strings, @multiples);
    }
    push (@$results, [@result_strings]);
    return;
}

#
# Main driver to init/sort our input data and make results in a form the
#   output sub will use.  This sub was/is used to test different ways to
#   structure both the input and output without changing callers or
#   underlying subs as I went through many iterations.
#
sub Solve {
    my ($price_target,$dish_prices_ref) = @_;

    my @values = @$dish_prices_ref;
    my @results;
    @values = sort {$b <=> $a} map {[$_, 0]} @values; # Generate counters and init to 0
    subSums (\@results,\@values, $price_target, 0);
    return @results;
}
