/****************************************************************************
 * Copyright (c) 2020 Mike Sharkey <mike@pikeaero.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a 
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense, 
 * and/or sell copies of the Software, and to permit persons to whom the 
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
 * DEALINGS IN THE SOFTWARE.
 ****************************************************************************/
#include <iostream>
#include <fstream>
#include <string>

using namespace std;

#include <string.h>
#include <time.h>
#include <dbg816.h>

#define	RAM_SIZE	(512 * 1024)
#define MEM_MASK	(512 * 1024L - 1)

bool debug=false;
load816* vm=NULL;

// Initialise the vm
inline void setup()
{
	vm->setMemory(MEM_MASK, RAM_SIZE, NULL);
}

//==============================================================================
// Command Handler
//------------------------------------------------------------------------------

int main(int argc, char **argv)
{
	int	index = 1;

	while (index < argc) {
		if (argv[index][0] != '-') break;

		if (!strcmp(argv[index], "-d")) {
			debug=true;
			++index;
			continue;
		}

		if (!strcmp(argv[index], "-?")) {
			cerr << "Usage: emu816 [-d] s19/28-file ..." << endl;
			return (1);
		}

		cerr << "Invalid: option '" << argv[index] << "'" << endl;
		return (1);
	}

    vm = debug ? (new dbg816) : (new load816);
	setup();

	if (index < argc)
		do {
			if ( !vm->load(argv[index]) )
            {
                cerr << "load failed '" << argv[index] << "'";
                exit(-1);
            }
            ++index;
		} while ( index < argc);
	else {
		cerr << "No S28 files specified" << endl;
		return (1);
	}

	timespec start, end;

	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &start);

	vm->reset();
	vm->run();

	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &end);

	double secs = (end.tv_sec + end.tv_nsec / 1000000000.0)
		    - (start.tv_sec + start.tv_nsec / 1000000000.0);

	double speed = vm->cycles() / secs;

	cout << endl << "Executed " << vm->cycles() << " in " << secs << " Secs";
	cout << endl << "Overall CPU Frequency = ";
	if (speed < 1000.0)
		cout << speed << " Hz";
	else {
		if ((speed /= 1000.0) < 1000.0)
			cout << speed << " KHz";
		else
			cout << (speed /= 1000.0) << " Mhz";
	}
	cout << endl;

    delete vm;

	return(0);
}