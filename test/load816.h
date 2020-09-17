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
#ifndef LOAD816_H
#define LOAD816_H

#include <vm816.h>
#include <stdlib.h>
#include <stdint.h>
#include <srecreader.h>

#define LOAD816_MAX_LINE    780

class load816 : public vm816
{
    public:

        load816(const char* name=NULL);
        virtual ~load816();

        bool                load(const char* name=NULL);

        int                 cb_meta_fn(srec_reader_t* srec_state);
        int                 cb_store_fn(srec_reader_t* srec_state);
        int                 cb_term_fn(srec_reader_t* srec_state);

    private:

        const char*         m_name;
        srec_reader_t       m_srec_state;
        FILE*               m_file;
        char                m_line[LOAD816_MAX_LINE];
        bool                m_success;
};

#endif 
