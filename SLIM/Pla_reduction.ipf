#pragma rtGlobals=3		// Use modern global access method.
#pragma IgorVersion = 6.2

// SVN date:    $Date$
// SVN author:  $Author$
// SVN rev.:    $Revision$
// SVN URL:     $HeadURL$
// SVN ID:      $Id$

//TODO all distances, chopper frequencies should be read from NeXUS file

#include "Pla_catalogue"
#include "Pla_nsplice"
#include "Pla_peakfinder"
#include "Pla_rebin"
#include "Pla_reduction2"
#include "Pla_Reduction3"
#include "Pla_Xrayreduction"
#include "Pla_streamer"
#include "EP_errorPropagation"
#include "Pla_reductionPOL"
#include "Pla_reductionPOLCORRECT"

//opening of the choppers, in radians
	Constant O_C1 = 1.04719755
	Constant O_C2 = 0.17453293
	Constant O_C3 = 0.43633231
	Constant O_C4 = 1.04719755
	Constant O_C1d = 60
	Constant O_C2d = 10
	Constant O_C3d = 25
	Constant O_C4d = 60

	Constant DISCRADIUS = 350
	
	//default distances.  These should normally be read from the NeXUS file.
	constant C_CHOPPER1_DISTANCE = 0
	constant C_CHOPPER2_DISTANCE = 103
	constant C_CHOPPER3_DISTANCE = 359
	constant C_CHOPPER4_DISTANCE = 808
	constant C_SLIT2_DISTANCE = 1909.9
	constant C_SLIT3_DISTANCE = 4846.4
	constant C_GUIDE1_DISTANCE = NaN
	constant C_GUIDE2_DISTANCE = NaN
	constant C_SAMPLE_DISTANCE = 5045.4

	//Physical Constants
	Constant PLANCK = 6.624e-34
	Constant NEUTRONMASS = 1.6749286e-27
	Constant P_MN = 3.95603e-7
	
	//the constants below may change frequently
	Constant Y_PIXEL_SPACING = 0.321	//in mm
	Constant CHOPFREQ = 24		//Hz
	Constant ROUGH_BEAM_POSITION = 500		//Rough direct beam position
	constant ROUGH_BEAM_WIDTH = 10
	Constant CHOPPAIRING = 3
		
	//We'll have two
	//StrConstant PATH_TO_DATA = "Macintosh HDD:Users:andrew:Documents:Andy:Platypus:TEMP:"

Function/s reduceASingleFile(inputPathStr, outputPathStr, scalefactor,runfilename, lowlambda, highlambda, rebin, [scanpointrange, timeslices, water, background, expected_peak, actual_peak, manual, dontoverwrite, normalise, saveSpectrum, saveoffspec, verbose])
	string inputPathStr, outputPathStr
	variable scalefactor
	string runfilename
	variable lowLambda,highLambda, rebin
	string scanpointrange
	Wave/z timeslices
	string water
	variable background
	variable/c expected_peak, actual_peak
	variable manual, dontoverwrite, normalise, saveSpectrum, saveoffspec, verbose
	
	//produces a reflectivity curve for a given angle
	//ONLY ONE ANGLE IS REDUCED
	//returns the unique reduced file name if succesful, or a 0 length string otherwise
	
//	inputPathStr - string containing the place where the data resides, e.g. "C:platypus:My Documents:Desktop:data"
//	outputPathStr - string containing the place where the reduced data will reside, e.g. "C:platypus:My Documents:Desktop:data:output"
//	
//	scalefactor - data is divided by this variable to produce a correct critical edge, should normally be 1.
//	
//	runfilename - string containing run names for the reflected and direct beams in key:value form, i.e. - "PLP0003011:PLP0003010" (reflected:direct)
//	
//	lowlambda - variable specifying the low wavelength cutoff (Angstrom)
//	
//	highlambda - variable specifying the high wavelength cutoff (Angstrom)
//	
//	rebin - variable specifying the rebin percentage, e.g 3 for 3% dq/q rebinning.
//	
//	OPTIONAL
//	scanpointrange -  if a datafile contains several images this string controls which are processed. e.g. "1>20"
//	would integrate points 1 to 20 from the reflected beam run. (counting starts from 0).  If you set the range to -1,
//   then individual scans in a single file are reduced separately. If the range isn't specified then individual scans in a single file are integrated. 
//	 If there is only one scan point (specified, or not specified) AND the eventStreaming variable > 0, then the neutron events are split into different images.  This is useful for kinetic data.
//	
//	timeslices - IFF you wish to do event streaming you should set this wave with the timeslices filled out (the bin edges in seconds).   The DAQ_ directory
//                          should be present in the input directory.
//	
//	water - string containing the water runfile for detector normalisation
//	
//	background - variable specifying whether you want to subtract background (1=true, 0 = false), 1 is default.
//	
//	expected_centre - variable specifying where you expect to see the specular ridge, in detector pixels
//	
//	manual - variable specifying  whether you would like to manually choose beam centres/FWHM, otherwise it is done automatically
//	
//	dontoverwrite = variable specifying if you want to create unique names everytime you reduce the file. (default == 1)
//	
//	normalise - variable specifying whether you want to normalise by beam monitor counts (default == 1)
//	
//	saveSpectrum - variable specifying whether you want to normalise by beam monitor counts (default == 0)
//	
//	 saveoffspec - variable specifying whether you want to save the offspecular reflectivity map (default == 0)
//	
//	verbose - variable specifying if you want verbose output (default == 1)
	
	//this function must load the data using loadNexusfile, then call processNexusfile which produces datafolders containing
	//containing the spectrum (W_spec, W_specSD, W_lambda, W_lambdaSD,W_specTOFHIST,W_specTOF,W_LambdaHIST)

	//to create reflectivity one simply divides the reflected spectrum by the direct spectrum.
	//Remembering to propagate the errors in quadrature.
	//A resolution wave is also calculated.  The wavelength contribution is calculated in processNexusfile
	//the angular part is calculated here.
	
	//writes out the file in Q <tab> R <tab> dR <tab> dQ format.
	string tempStr,cDF,directDF,angle0DF, alreadyLoaded="", toSplice="", direct = "", angle0="",tempDF, reductionCmd, cmd = "", fname,ofname
	variable ii,D_S2, D_S3, D_SAMPLE,domega, spliceFactor,temp, isDirect, aa,bb,cc,dd,jj,kk, numspectra, fileID
	
	cDF = getdatafolder(1)
	
	//setup the datafolders
	Newdatafolder/o root:packages
	Newdatafolder /o root:packages:platypus
	Newdatafolder /o root:packages:platypus:data
	//directory for the reduction package
	Newdatafolder /o root:packages:platypus:data:Reducer
	tempDF = "root:packages:platypus:data:Reducer:"
	
	//set up the default parameters
	if(paramisdefault(water))
		water = ""
	endif
	if(paramisdefault(scanpointrange))
		scanpointrange = ""
	else
		scanpointrange = replacestring(" ", scanpointrange, "")
	endif
	if(paramisdefault(background))
		background = 1
	endif
	if(paramisdefault(expected_peak))
		expected_peak = cmplx(ROUGH_BEAM_POSITION, NaN)
	endif
	if(paramisdefault(manual))
		manual = 0
	endif
	if(paramisdefault(dontoverwrite))
		dontoverwrite = 1
	endif
	if(paramisdefault(normalise))
		normalise = 1
	endif
	if(paramisdefault(saveSpectrum))
		saveSpectrum = 0
	endif
	if(paramisdefault(saveoffspec))
		saveoffspec = 0
	endif
	if(paramisdefault(water))
		water = ""
	endif
	if(paramisdefault(verbose))
		verbose = 1
	endif
	
	//create the reduction string for this particular operation.  THis is going to be saved in the datafile.
	cmd = "reduceASingleFile(\"%s\",\"%s\",%g,\"%s\",%g,%g,%g,background = %g, scanpointrange=\"%s\", eventstreaming=%s,water=\"%s\", expected_peak=cmplx(%g,%g), manual = %g, dontoverwrite = %g, normalise = %g, saveSpectrum = %g, saveoffspec=%g)"
	sprintf reductionCmd, cmd, inputPathStr, outputPathStr, scalefactor, runfilename, lowLambda, highLambda, rebin, background, scanpointrange, nameofwave(timeslices), water, real(expected_peak), imag(expected_peak), manual, dontoverwrite, normalise, saveSpectrum,saveoffspec
	if(verbose)
		print reductionCmd
	endif
	try
		setdatafolder "root:packages:platypus:data:Reducer"
		//set the data to load
		
		GetFileFolderInfo/q/z inputPathStr
		if(V_flag)//path doesn't exist
			print "ERROR please give valid input path (reduce)";abort
		endif		
		GetFileFolderInfo/q/z outputPathStr
		if(V_flag)//path doesn't exist
			print "ERROR please give valid output path (reduce)";abort
		endif

		//check the scalefactor is reasonable
		if(numtype(scalefactor) || scalefactor==0)
			print "ERROR a non sensible scale factor was entered (reduce) - setting scalefactor to 1";	
			scalefactor = 1 
		endif
		//check that low lambda, high lambda + rebin are reasonable
		if(lowlambda < 0 || lowlambda>highlambda || lowlambda >20 || numtype(lowlambda))
			print "ERROR set a reasonable value for low lambda cutoff";	abort
		endif
		if(highlambda < 0 || highlambda >30|| numtype(highlambda))
			print "ERROR set a reasonable value for high lambda cutoff";	abort
		endif
		if(rebin <0 || rebin >15 || numtype(rebin))
			print "ERROR rebin should be 0<rebin<15 (reduce)"; 
			print "defaulting to 1%"
			rebin = 1
		endif
	
		//iterate through the runnames and check they're valid
		if(itemsinlist(runfilename) == 0)
			print "ERROR no runs will be reduced if you don't give any (reduceASingleFile)";abort
		endif
		
		if(!paramisdefault(water) && strlen(water)>0)
			if(loadNexusFile(inputPathStr, water, outputPathStr = outputpathStr))
				print "Error loading water run (reduce)"
				abort
			endif
		endif
		
		//make the rebin wave, to rebin both direct and reflected data
		if(rebin)
			Wave W_rebinboundaries = Pla_gen_binboundaries(lowlambda, highlambda, rebin)
		endif
	
		//now reduce the data, figure out the direct and reflected run names.
		angle0 = stringfromlist(0, runfilename, ":")
		direct = stringbykey(angle0, runfilename)
			
		if(strlen(angle0)==0 || strlen(direct)==0)
			print "ERROR parsing the runfilenamestring (reduceASingleFile)"; abort
		endif
		
		//start off by processing the direct beam run
		isDirect = 1
		if(rebin)
			if(processNeXUSfile(inputPathStr, outputPathStr, direct, background, lowLambda, highLambda, water = water, isDirect = isDirect, expected_peak = expected_peak, rebinning = W_rebinboundaries, manual = manual, normalise=normalise, saveSpectrum = saveSpectrum))
				print "ERROR while processing a direct beam run (reduceASingleFile)" ; abort
			endif
		else
			if(processNeXUSfile(inputPathStr, outputPathStr, direct, background, lowLambda, highLambda, water = water, isDirect = isDirect, expected_peak = expected_peak, manual = manual, normalise = normalise, saveSpectrum = saveSpectrum))
				print "ERROR while processing a direct beam run (reduceASingleFile)" ; abort
			endif				
		endif

		directDF = "root:packages:platypus:data:Reducer:"+cleanupname(removeending(direct,".nx.hdf"),0)
		if(!datafolderexists(directDF))
			Print "ERROR, direct beam not loaded: (reduceASingleFile)"; abort
		endif
			
		Wave M_specD = $(directDF+":M_spec"); AbortOnRTE
		Wave M_specDSD = $(directDF+":M_specSD"); AbortOnRTE			
		Wave M_topandtailD = $(directDF+":M_topandtail"); AbortOnRTE			
		Wave W_lambdaD = $(directDF+":M_lambda"); AbortOnRTE
		Wave M_lambdaHISTD = $(directDF+":M_lambdaHIST"); AbortOnRTE
		Wave/z M_uncorrectedGravityCentre = $(directDF+":M_uncorrectedgravityCentre"); AbortOnRTE
		Wave DetectorPosD = $(directDF+":instrument:detector:longitudinal_translation"); AbortOnRTE
		Wave DetectorHeightD = $(directDF+":instrument:detector:vertical_translation")
		Wave M_directbeampos = $(directDF+":M_beampos"); AbortOnRTE
		
		//load in and process reflected angle
		//when you process the reflected nexus file you have to use the lambda spectrum from the direct beamrun
		make/n=(dimsize(M_lambdaHISTD, 0))/free/d W_lambdaHISTD
		W_lambdaHISTD[] = M_lambdaHISTD[p][0]
		if(processNeXUSfile(inputPathStr, outputPathStr, angle0, background, lowLambda, highLambda, scanpointrange = scanpointrange, timeslices = timeslices, water = water, isDirect = 0, expected_peak = expected_peak, rebinning = W_lambdaHISTD, manual=manual, normalise = normalise, saveSpectrum = saveSpectrum))
			print "ERROR while processing a reflected beam run (reduce)" ; abort
		endif
		
		//check that the angle0 data has been loaded into a folder and processed
		angle0DF = "root:packages:platypus:data:Reducer:"+cleanupname(removeending(angle0,".nx.hdf"),0)
		if(!datafolderexists(angle0DF))
			Print "ERROR, data from angle file "+ angle0 + " not loaded: (reduce)"
			abort
		endif
		
		//create a string to hold the reduction string.
		string/g $(angle0DF+":reductionCmd") = reductionCmd
		
		Wave M_specA0 = $(angle0DF+":M_spec"); AbortOnRTE
		Wave M_specA0SD = $(angle0DF+":M_specSD"); AbortOnRTE
		Wave M_topandtailA0 = $(angle0DF+":M_topandtail"); AbortOnRTE
		Wave M_topandtailA0SD = $(angle0DF+":M_topandtailSD"); AbortOnRTE

		numspectra = dimsize(M_specA0, 1)
		
		Wave DetectorPosA0 = $(angle0DF+":instrument:detector:longitudinal_translation"); AbortOnRTE
		Wave M_beamposA0 = $(angle0DF+":M_beampos"); AbortOnRTE
		Wave DetectorHeightA0 = $(angle0DF+":instrument:detector:vertical_translation")

		Wave sth = $(angle0DF+":sample:sth"); AbortOnRTE
		
		if((DetectorPosA0[0] - DetectorPosD[0])>0.1)
			Print "ERROR, detector dy for direct and reduced data not the same: (reduce)"; abort
		endif
		
		//work out the actual angle of incidence from the peak position on the detector
		//this will depend on the mode
		Wave/t mode = $(angle0DF+":instrument:parameters:mode")
		//create an omega wave
		Wave M_lambda = $(angle0DF+":M_lambda"); AbortOnRTE
		Wave M_lambdaHIST = $(angle0DF+":M_lambdaHIST"); AbortOnRTE
		Wave M_specTOFHIST = $(angle0DF+":M_specTOFHIST"); AbortOnRTE
		Wave M_specTOF = $(angle0DF+":M_specTOF"); AbortOnRTE

		duplicate/o M_lambda, $(angle0DF+":omega")
		Wave omega = $(angle0DF+":omega")
		//create a twotheta wave, and a qz, qx wave
		duplicate/o M_topandtailA0, $(angle0DF + ":M_twotheta")
		duplicate/o M_topandtailA0, $(angle0DF + ":M_omega")
		duplicate/o M_topandtailA0, $(angle0DF + ":M_qz")	
		duplicate/o M_topandtailA0, $(angle0DF + ":M_qy")					
		duplicate/o M_topandtailA0, $(angle0DF + ":M_qzSD")			
		duplicate/o M_topandtailA0, $(angle0DF + ":M_ref")
		duplicate/o M_topandtailA0, $(angle0DF + ":M_refSD")
		duplicate/free M_lambdaHIST, M_qHIST
		Wave M_twotheta = $(angle0DF + ":M_twotheta")
		Wave M_omega = $(angle0DF + ":M_omega")
		Wave M_qz = $(angle0DF + ":M_qz")
		Wave M_ref = $(angle0DF + ":M_ref")
		Wave M_refSD = $(angle0DF + ":M_refSD")
		Wave M_qy = $(angle0DF + ":M_qy")
		Wave M_qzSD = $(angle0DF + ":M_qzSD")

		variable loPx, hiPx
		loPx = numberbykey( "loPx", note(M_topandtailA0))
		hiPx = numberbykey("hiPx", note(M_topandtailA0))
		
		strswitch(mode[0])
			case "FOC":
			case "POL":
			case "POLANAL":
			case "MT":
				//					omega = Pi*sth[0]/180
				multithread omega[][] = atan(((M_beamposA0[p][q] + DetectorHeightA0[0]) - (M_directbeampos[p][0] + DetectorHeightD[0]))/DetectorposA0[0])/2
				multithread M_twotheta[][][] = atan((( (q * Y_PIXEL_SPACING) + DetectorHeightA0[0]) - (M_directbeampos[p][0] + DetectorHeightD[0]))/DetectorposA0[0])
				if(omega[0][0] < 0)
					omega = 0 - omega
					M_twotheta = 0 - M_twotheta
				endif
				break
			case "SB":
				//					Wave m1ro =  $(angle0DF+":instrument:collimator:rotation");ABORTonRTE
				//					omega = m1ro[0]
				multithread omega[][] = atan(((M_beamposA0[p][q] + DetectorHeightA0[0]) - (M_directbeampos[p][0] + DetectorHeightD[0]))/(2*DetectorposA0[0]))
				multithread M_twotheta[][][] = omega[p][r] + atan((((q * Y_PIXEL_SPACING) + DetectorHeightA0[0]) - (M_directbeampos[p][0] + DetectorHeightD[0]) - (DetectorposA0[0] * tan(omega[p][r])))/DetectorposA0[0])
				break
			case "DB":		//angle of incidence for DB is always 4.8
				//					omega = 4.8 * Pi/180
				multithread omega[][] = atan(((M_beamposA0[p][q] + DetectorHeightA0[0]) - (M_directbeampos[p][0] + DetectorHeightD[0]))/(2*DetectorposA0[0]))
				multithread M_twotheta[][][] = omega[p][r]+ atan((((q * Y_PIXEL_SPACING) + DetectorHeightA0[0]) - (M_directbeampos[p][0] + DetectorHeightD[0]) - (DetectorposA0[0] * tan(omega[p][r])))/DetectorposA0[0])
				break
		endswitch
		print "corrected angle of incidence for ",angle0, " is: ~",180*omega[0][0]/pi

		//within the specular band omega changes slightly
		//used for constant Q integration.
		multithread M_omega = M_twotheta/2
		
		//now normalise the counts in the reflected beam by the direct beam spectrum
		//this gives a reflectivity
		//and propagate the errors
		//this step probably produces negative reflectivities, or NaN if M_specD is 0.
		//ALSO, 
		//M_refSD has the potential to be NaN is M_topandtailA0 or M_specD is 0.
		M_refSD = 0	
		M_ref = 0
		multithread M_refSD[][][] = sqrt(((M_topandtailA0SD[p][q][r] / M_specD[p][0])^2 + (M_topandtailA0[p][q][r]^2 / (M_specD[p][0]^4)) * M_specDSD[p][0]^2))
		multithread M_ref[][][] = M_topandtailA0[p][q][r] / M_specD[p][0]
				
		//scale reflectivity by scale factor
		// because refSD is stil fractional variance (dr/r)^2 have to divide by scale factor squared.
		multithread M_ref /= scalefactor
		multithread M_refSD /= (scalefactor)

		//now calculate the Q values for the detector pixels.  Each pixel has different 2theta and different wavelength, ASSUME that they have the same angle of incidence
		multithread M_qz[][][]  = 2 * Pi * (1 / M_lambda[p][r]) * (sin(M_twotheta[p][q][r] - omega[p][r]) + sin(M_omega[p][q][r]))
		multithread M_qy[][][] = 2 * Pi * (1 / M_lambda[p][r]) * (cos(M_twotheta[p][q][r] - omega[p][r]) - cos(M_omega[p][q][r]))

		//work out the uncertainty in Q.
		//the wavelength contribution is already in W_LambdaSD
		//now have to work out the angular part and add in quadrature.
		Wave M_lambdaSD = $(angle0DF+":M_lambdaSD"); AbortOnRTE
		multithread M_qzSD[][][] = (M_lambdaSD[p][r] / M_lambda[p][r])^2
		
		//angular part of uncertainty
		Wave ss2vg = $(angle0DF+":instrument:slits:second:vertical:gap")
		Wave ss3vg = $(angle0DF+":instrument:slits:third:vertical:gap")
		Wave slit2_distance = $(angle0DF+":instrument:parameters:slit2_distance")
		Wave slit3_distance = $(angle0DF+":instrument:parameters:slit3_distance")
		D_S2 = slit2_distance[0]
		D_S3 = slit3_distance[0]
		domega = 0.68 * sqrt((ss2vg[0]^2 + ss3vg[0]^2) / ((D_S3 - D_S2)^2))
		
		//now calculate the full uncertainty in Q for each Q pixel
		multithread M_qzSD[][][] += (domega/omega[p][r])^2
		multithread M_qzSD = sqrt(M_qzSD)
		multithread M_qzSD *= M_qz
				
			
			
		//now cut out the pixels that aren't in the reflected beam
		//			deletepoints/M=1 hiPx+1, dimsize(M_ref,1), M_ref,M_refSD, M_qz, M_qzSD, M_omega, M_twotheta
		//			deletepoints/M=1 0, loPx, M_ref,M_refSD, M_qz, M_qzSD, M_omega, M_twotheta

		//get a beam profile for normalisation, not all pixels contribute equally to the reflectivity signal
		//			make/o/d/n=(hiPx-loPx+1)  $(angle0DF + ":beam_profile")
		//			Wave beam_profile = $(angle0DF + ":beam_profile")
		//			for(jj=0 ; jj< numpnts(beam_profile) ; jj+=1)
		//				imagetransform/g=(loPx+jj) sumcol M_topandtailA0
		//				beam_profile[jj] = V_Value
		//			endfor		
		//			Wavestats/q/m=1 beam_profile
		//			beam_profile /= (V_sum)
		//			M_ref[][] *= (beam_profile[q])

		/////////////////////////////
		/////////////////////////////
		//constant wavelength binning, comment out if performing constant Q
		/////////////////////////////
		/////////////////////////////
		make/n=(dimsize(M_qHIST, 0) - 1, numspectra)/free/d W_q = 0, W_qSD = 0, W_ref = 0, W_refSD = 0

		Multithread W_q[][] = LambdaToQ(M_lambda[p][q], omega[p][q])			
		Multithread W_qSD[][] = (M_lambdaSD[p][q]/M_lambda[p][q])^2+(domega/omega[p][q])^2
		Multithread W_qSD = sqrt(W_qSD)
		Multithread W_qSD *= W_q

		duplicate/free M_ref, M_reftemp
		duplicate/free M_refSD, M_refSDtemp

		deletepoints/M=1 hiPx + 1, dimsize(M_ref, 1), M_reftemp, M_refSDtemp
		deletepoints/M=1 0, loPx, M_reftemp, M_refSDtemp

		for(ii = 0 ; ii < numspectra ; ii += 1)
			imagetransform/P=(ii) sumallrows M_reftemp
			Wave W_sumrows
			W_ref[][ii] = W_sumrows[p]
			
			for(jj = 0 ; jj < dimsize(M_reftemp, 1) ; jj += 1)
				W_refSD[][ii] += M_refSDtemp[p][jj][ii]^2
			endfor
		endfor
		W_refSD = sqrt(W_refSD)	

		/////////////////////////////
		/////////////////////////////			
		//Constant Q - doesn't work at the moment
		/////////////////////////////
		/////////////////////////////
		//work out Q bins			
		//			histtopoint(W_qHIST)
		//			Wave W_point
		//			duplicate/o W_point, $(angle0DF + ":W_q")
		//			duplicate/o W_point, $(angle0DF + ":W_qSD")
		//			Wave W_q = $(angle0DF + ":W_q")
		//			Wave W_qSD = $(angle0DF + ":W_qSD")
		//			LambdatoQ(W_qHIST, W_lambdaHIST, omega)
		//			LambdatoQ(W_q, W_lambda, omega)
		//			//assume that W_qSD is the same as the middle row.
		//			W_qSD[] = M_qzSD[p][dimsize(M_qzSD,1)/2]
		//			
		//			Pla_histogram(W_qHIST, M_qz, M_ref, M_refSD)
		//			Wave W_signal, W_signalSD, W_binfiller
		//			duplicate/o W_signal, $(angle0DF + ":W_ref")
		//			duplicate/o W_signalSD, $(angle0DF + ":W_refSD")
		//			killwaves/Z W_signal, W_signalSD
		//			Wave W_ref = $(angle0DF + ":W_ref")
		//			Wave W_refSD = $(angle0DF + ":W_refSD")
		//			//			W_ref/=W_binfiller
		//			//			W_refSD/=W_binfiller
		//			
		//			//now we have to get rid of points at the start and end, because const Qz is diagonal on the detector - some Qz bins
		//			//are filled with a lot fewer points, it's just easiest to delete them.
		//			//Do the low Q end first (highest bin number).
		//			//work out the highest Qz value, this will be at the top left
		//			//need to work out which W_qHIST bin it falls into
		//			variable loQcutoff = binarysearch(W_qHIST, M_qz[inf][inf])
		//			variable hiQcutoff = binarysearch(W_qHIST, M_qz[0][0])
		//			//need to get rid of all Q points higher than this.  First for the point values, then for the histoversions
		//			deletepoints/M=0 loQcutoff+1, dimsize(W_q,0), W_q, W_ref,W_refSD, W_qSD, W_lambda
		//			deletepoints/M=0 loQcutoff+1, dimsize(W_q,0), W_beamposA0, W_specA0, W_specA0SD, W_specTOF, M_topandtailA0
		//			deletepoints/M=0 loQcutoff+1, dimsize(W_q,0), M_topandtailA0SD, W_lambdaSD, omega, M_qz, M_ref, M_refSD, M_qzSD, M_omega, M_twotheta
		//			deletepoints/M=0 loQcutoff+2, dimsize(W_qHIST,0), W_qHIST, W_specTOFHIST, W_lambdaHIST
		//			
		//			deletepoints/M=0 0, hiQcutoff, W_q, W_ref,W_refSD, W_qSD, W_lambda
		//			deletepoints/M=0 0, hiQcutoff, W_beamposA0, W_specA0, W_specA0SD, W_specTOF, M_topandtailA0
		//			deletepoints/M=0 0, hiQcutoff, M_topandtailA0SD, W_lambdaSD, omega, M_qz, M_ref, M_refSD, M_qzSD, M_omega, M_twotheta
		//			deletepoints/M=0 0, hiQcutoff, W_qHIST, W_specTOFHIST, W_lambdaHIST		
			
		//
		//now write the individual wave out to a file.  It is reverse sorted in q, sorted in lambda, and we want to keep that.
		//therefore SORT->WRITE->REVERSE SORT
		//
		make/n=(dimsize(W_q, 0))/d/o $(angle0DF+ ":qq"), $(angle0DF+ ":RR"), $(angle0DF+ ":dR"), $(angle0DF+ ":dQ")
		Wave qq = $(angle0DF+ ":qq")
		Wave RR = $(angle0DF+ ":RR")
		Wave dR = $(angle0DF+ ":dR")
		Wave dQ = $(angle0DF+ ":dQ")
		make/n=(dimsize(M_ref, 0), dimsize(M_ref, 1))/free/d qz2D, qy2D, RR2d, EE2d 
		
		for(ii = 0 ; ii < numspectra ; ii += 1)
			RR[] = W_ref[p][ii]
			dR[] = W_refSD[p][ii]
			qq[] = W_q[p][ii]
			dQ[] = W_qSD[p][ii]
	
			Sort qq, qq, RR, dR, dQ
			
			fname = cutfilename(angle0)
			if(dontoverwrite)
				fname = uniqueFileName(outputPathStr, fname, ".dat")
			endif
			newpath/o/q/z pla_temppath_write, outputpathStr
			open/P=pla_temppath_write fileID as fname + ".dat"
			
			if(V_flag == 0)
				fprintf fileID, "Q (1/A)\t Ref\t dRef (SD)\t dq(FWHM, 1/A)\n"
				wfprintf fileID, "%g\t %g\t %g\t %g\n" qq, RR, dR, dQ
				close fileID
			endif
			
			//this only writes XML for a single file
			fname = cutfilename(angle0)
			if(dontoverwrite)
				fname = uniqueFileName(outputPathStr, fname, ".xml")
			endif
			Wave/t user = $(angle0DF + ":user:name")
			Wave/t samplename = $(angle0DF + ":sample:name")			
			writeSpecRefXML1D(outputPathStr, fname, qq, RR, dR, dQ, "", user[0], samplename[0], angle0, reductionCmd)
			
			//calculate the actual PDF for the resolution function, for each point
			if(paramisdefault(timeslices))
				//you are not event streaming, so there will be numspectra entries for slit info (etc) in the HDF file
				assignActualKernel(angle0DF, directDF, W_q,  ii)
				Wave resolutionkernel = $(angle0DF + ":resolutionkernel")
			else
				//there aren't numspectra entries in the HDF file for slit info (etc), should give assignactualkernel
				//the actual scan point being used.  In the absence of using the scan point range (faff to calculate it),
				//just use the first scan point
				assignActualKernel(angle0DF, directDF, W_q,  0)
				Wave resolutionkernel = $(angle0DF + ":resolutionkernel")			
			endif
				
			//write an HDF file for a single file
			fname = cutfilename(angle0)
			if(dontoverwrite)
				fname = uniqueFileName(outputPathStr, fname, ".h5")
			endif
			writeSpecRefH5_1D(outputPathStr, fname, qq, RR, dR, dQ, resolutionkernel = resolutionkernel)
									
			//write a 2D XMLfile for the offspecular data
			if(saveoffspec)
				Multithread qz2D[][] = M_qz[p][q][ii]
				Multithread qy2D[][] = M_qy[p][q][ii]
				Multithread RR2d[][] = M_Ref[p][q][ii]
				Multithread EE2d[][] = M_RefSD[p][q][ii]
							
				ofname = "off_" + cutfilename(angle0)
				if(dontoverwrite)
					fname = uniqueFileName(outputPathStr, ofname, ".xml")
				endif
				write2DXML(outputPathStr, ofname, qz2D, qy2D, RR2d, EE2d, "", user[0], samplename[0], angle0, reductionCmd)
			endif
		endfor
		
		killpath/z pla_temppath_write	
	catch		
		Print "ERROR: an abort was encountered in (reduceASingleFile)"
		setdatafolder $cDF
		return ""
	endtry

	setdatafolder $cDF
	return fname
End


Function reduce(inputPathStr, outputPathStr, scalefactor,runfilenames, lowlambda, highlambda, rebin, [water, background, expected_peak, manual, dontoverwrite, normalise, saveSpectrum, saveoffspec, verbose])
	string inputPathStr, outputPathStr
	variable scalefactor
	string runfilenames
	variable lowLambda,highLambda, rebin
	string water
	variable background
	variable/c expected_peak
	variable manual, dontoverwrite, normalise, saveSpectrum, saveoffspec, verbose
	
	//produces a reflectivity curve for a given set of angles
	//if you want to do kinetic reduction (e.g.  you want to examine streamed data, or reduce the individual plots within a single file) use reduceASingleFile directly
	//returns 0 if successful, non zero otherwise
	//see reduceASingleFile for documentation

	string cDF, toSplice=""
	string  fname, cmd = "", thePair, ifname
	variable ii, spliceFactor, numpairs
	
	cDF = getdatafolder(1)	
	try
		numpairs = itemsinlist(runfilenames)
		for(ii = 0 ; ii < numpairs ; ii += 1)
			thePair = stringfromlist(ii, runfilenames)
			ifname = reduceASingleFile(inputPathStr, outputPathStr, scalefactor, thePair, lowlambda, highlambda, rebin, water=water, scanpointrange = "", background=background, expected_peak=expected_peak, manual=manual, dontoverwrite=dontoverwrite, normalise=normalise, saveSpectrum=savespectrum, saveoffspec=saveoffspec,verbose=verbose)
			if(strlen(ifname) == 0)
				print "ERROR whilst calling reduceasinglefile (reduce)"
				abort
			else
				toSplice += ifname + ";"
			endif
		endfor
		if(dontoverwrite)
			fname = uniqueFileName(outputPathStr, "c_" + stringfromlist(0, toSplice), ".xml")
		else
			fname = "c_" + stringfromlist(0, toSplice)
		endif	

		if(itemsinlist(toSplice) > 0)
			sprintf cmd, "splicefiles(\"%s\",\"%s\",\"%s\",rebin = %g)", outputPathStr, fname, toSplice, rebin
			print cmd
		
			if(spliceFiles(outputPathStr, fname, toSplice, rebin = rebin))
				print "ERROR while splicing (reduce)";abort
			endif
		endif
		
		//once you've written the spliced file try to write it into an HDF file.
	catch
		
		Print "ERROR: an abort was encountered in (reduce)"
		setdatafolder $cDF
		return 1
	endtry

	setdatafolder $cDF
	return 0
End

Function sumWave(wav, p1, p2)
	Wave wav
	variable p1, p2
	variable summ, ii, temp
	if(p2 < p1)
		temp = p2
		p2 = p1
		p1 = temp
	endif

	for(ii = 0 ; ii < p2; ii += 1)
		summ += wav[ii]
	endfor
	return summ
end

Function/s cutFileName(filename)
	string filename
	//this function cuts a filename like "PLP00000054" down to "PLP54"
	//returns the shortened name as a string.
	variable ii
	string ret = ""
	
	return filename
	
	variable len = strlen(filename)
	variable isNumber = 0
	for(ii=0 ; ii<len ; ii+=1)
		if(!stringmatch(filename[ii],"0"))
			ret+=filename[ii]
		endif
	endfor
	return ret
End

Function/s uniqueFileName(outputPathStr, filename, ext,[dontoverwrite])
	string outputPathStr, filename, ext
	variable dontoverwrite
	
	string theFiles, theUniqueName = ""
	variable ii
	
	if(paramisdefault(dontoverwrite))
		dontoverwrite =1
	endif
	GetFileFolderInfo/q/z outputPathStr
	if(V_flag)//path doesn't exist
		print "ERROR please give valid path (uniqueFileName)"
		return ""	
	endif
	newpath/o/q/z pla_temppath_write, outputPathStr		
	theFiles = indexedFile(pla_temppath_write, -1, ext)
	killpath/z pla_temppath_write
	theUniqueName = filename + "_0"
	
	if(!dontoverwrite)
		return theUniqueName
	endif
	
	//the file already exists, increment a number
	for(ii=1; whichListItem(theUniqueName + ext, theFiles) > -1 ; ii+=1)
		theUniqueName = filename + "_" + num2istr(ii)
	endfor 
	return theUniqueName
End

Function expandStrIntoPossibleFileName(fileStub, righteousFileName)
	//expands a possible fileStub into a correct Nexus filename.
	string fileStub, &righteousFileName

	string tempStr = ""
	variable size

	if(numtype(str2num(fileStub)) == 0)	//fileStub is a number like 302, so expand it to PLP0000203
		size = strlen(fileStub)
		if(str2num(fileStub) < 0 || size > 7)
			return 1
		endif
		sprintf tempstr, "PLP%0.7d.nx.hdf",str2num(fileStub)
	else			//the filestub begins with alphabetical characters, so the user probably supplied the whole thing, apart from the ending
		tempStr = fileStub + ".nx.hdf"
	endif

	righteousFileName = removeending(tempStr,".nx.hdf")
	return 0
End

Function loadNeXUSfile(inputPathStr, filename, [outputPathStr])
	string inputPathStr, fileName, outputPathStr
	//loads a NeXUS file, fileName, from the path contained in the inputPathStr string.  If it's not found in inputPathStr, try and find it in outputPathStr
	//returns 0 if successful, non zero otherwise
	
	string tempDF = "",cDF = "", temp
	variable fileRef, err, number

	cDF = getdatafolder(1)
	
	Newdatafolder/o root:packages
	Newdatafolder /o root:packages:platypus
	Newdatafolder /o root:packages:platypus:data
	Newdatafolder /o root:packages:platypus:data:Reducer
	
	GetFileFolderInfo/q/z inputPathStr
	if(V_flag)//path doesn't exist
		print "ERROR please give valid path (SLIM_PLOT_scans)"
		return 1	
	endif
	
	//full file path may be given
	filename = removeending(parsefilepath(0, filename, "*", 1, 0), ".nx.hdf")	
	sscanf filename, "PLP%d",number
	
	try
		//open the file and load the data
		tempDF = "root:packages:platypus:data:Reducer:"+cleanupname(removeending(filename,".nx.hdf"),0)
		for(;;)
			if(doesNexusfileExist(inputPathStr, filename+".nx.hdf"))
				newpath/o/q/z pla_temppath_loadNeXUSfile, inputpathStr
				hdf5openfile/P=pla_temppath_loadNeXUSfile/r/z fileRef as filename+".nx.hdf"
				break
			elseif(!paramisdefault(outputPathStr) && doesNexusfileExist(outputPathStr, filename+".nx.hdf"))
				newpath/o/q/z pla_temppath_loadNeXUSfile, outputpathStr
				hdf5openfile/P=pla_temppath_loadNeXUSfile/r/z fileRef as filename+".nx.hdf"
				break
			else
				doalert 1, "Couldn't find beam file: "+filename+". Do you want to try and download it from the server?"
				if(V_flag==2)
					print "ERROR: couldn't open beam file: (loadNexusfile)"; abort
				else
					if(downloadplatypusdata(inputpathStr=inputPathStr, lowFi = number, hiFi = number +1))
						print "ERROR while trying to download platypus data from server (loadNexusfile)";abort
					endif
				endif
			endif
		endfor
		newdatafolder/o $tempDF

		hdf5loadgroup/CONT=1/r/o/z $tempDF,fileRef,"entry1/"	
	catch
		if(fileRef)
			hdf5closefile fileRef
		endif
		setdatafolder $cDF
		killpath/z pla_temppath_loadNeXUSfile
		killdatafolder/z $tempDF	
		return 1
	endtry
	
	if(fileRef)
		hdf5closefile fileRef
	endif	
	setdatafolder $cDF
	killpath/z pla_temppath_loadNeXUSfile
	return 0
End

Function doesNexusfileExist(inputPathStr, filename)
	string inputPathStr, fileName
	
	newpath/o/q/z pla_temppath_doesNexusfileExist, inputpathStr
	string files = indexedfile(pla_temppath_doesNexusfileExist, -1, ".hdf")
	variable pos = whichlistitem(filename, files)
	killpath/z pla_temppath_doesNexusfileExist
	if(pos==-1)
		return 0
	else
		return 1
	endif
End

Function/wave getScanData(inputPathStr, filename)
//gets data of total_counts vs the scan variable for a given nexusfile
	String inputpathStr, fileName
	variable HDFref
	string cDF
	
	cDF = getdatafolder(1)
	
	GetFileFolderInfo/q/z inputpathStr
	if(V_flag)//path doesn't exist
		print "ERROR please give valid path (getScanData)"
		abort
	endif
	newpath/o/q/z pla_temppath_SLIM_plot_scans, inputpathStr

	DFREF tempDFR = newfreedatafolder()
	setdatafolder tempDFR
	
	try		
		HDF5openfile/p=pla_temppath_SLIM_plot_scans/z/r HDFref as filename
		if(V_flag)
			print "ERROR while opening HDF5 file (getScanData)"
			abort
		endif
		hdf5loaddata/z/q/o hdfref, "/entry1/data/total_counts"
		Wave total_counts = $(stringfromlist(0, S_wavenames))
		
		hdf5loaddata/z/q/o/A="axes" hdfref, "/entry1/data/hmm"
		Wave/t axes = $(stringfromlist(0, S_wavenames))
		string scanvariable = stringfromlist(0, axes[0], ":")

		hdf5loaddata/z/q/o hdfref, "/entry1/data/" + scanvariable
		Wave axisWav = $(stringfromlist(0, S_wavenames))
		
		setdatafolder $cDF
		make/n=(numpnts(total_counts), 3)/free/d scan
		scan[][0] = axisWav[p]
		scan[][1] = total_counts[p]
		scan[][2] = sqrt(total_counts[p])
		note scan, scanvariable
				
		if(HDFref)
			HDF5closefile/z HDFref
			killpath/z pla_temppath_SLIM_plot_scans
		endif		
		setdatafolder $cDF
		killpath/z pla_temppath_SLIM_plot_scans
		return scan
	catch
		if(HDFref)
			HDF5closefile/z HDFref
			killpath/z pla_temppath_SLIM_plot_scans
		endif
		setdatafolder $cDF
	endtry
End


Function processNeXUSfile(inputPathStr, outputPathStr, filename, background, loLambda, hiLambda[, water, scanpointrange, timeslices, isDirect, expected_peak, actual_peak, omega, two_theta,manual, saveSpectrum, rebinning, normalise,verbose, backgroundMask, dontoverwrite])
	string inputPathStr, outputPathStr, fileName
	variable background, loLambda, hiLambda
	string water, scanpointrange
	Wave/z timeslices
	variable isDirect
	variable/c expected_peak, actual_peak
	variable omega, two_theta, manual, saveSpectrum, normalise,verbose
	Wave/z backgroundMask
	variable dontoverwrite
	
	Wave/z rebinning
	//processes a  NeXUS file.
	//returns 0 if successful, non zero otherwise
	//pathname = string containing the path to the data
	//filename = filename for the spectrum, e.g. PLP0001000.  This is used to try and find a datafolder containing the loaded NeXUS data.
	//background = if you want to subtract a background, then set this variable equal to 1.
	//lolambda  = low wavelength cutoff for the spectrum
	//hiLambda = high wavelength cutoff for the spectrum
	//water is a filename for a normalisation run, typically a SANS scattering through a water cuvette.
	//expected_centre = pixel position for specular beam
	//expected_width = FWHM width in pixels of specular beam
	//manual = 1 for manual specification of specular ridge
	//rebinning = a wave containing new wavelength bins
	//isDirect = the spectrum is a direct beam measurement and gravity correction will ensue.
	//scanpointrange = if a datafile contains several images this variable controls which are processed.  If you omit this parameter SLIM will ask you which points you want to accumulate over
	// 					if you use a parameter with a null string, i.e. scanpointrange = "", then all scans are aggregated.  If you want to select a range specify it like   scanpointrange = "1>20".
	//					If you specify the scanpoint range "-1", then each spectrum is output individually.
	//timeslices = if there is only one spectrum to be processed (as would be the case if there is only one point in the file, or if the scanpoint range is e.g. 1>1) then this wave will cause the load
	//						of neutron event based data, but only if the wave is specified and there is more than 1 point in the wave. The wave contains the time slices for the framing.
	//saveSpectrumLoc = if this variable !=0 then the spectrum is saved to file.
	//backgroundMask - see topAndTail.  A way of specifying the exact points to calculate the background region.
	//dontoverwrite - if you are saving the spectrum, you possibly don't want to overwrite existing files.  Specify dontoverwrite=1 if you want a new file to be created.  Default is 0.....
	
	//first thing we will do is  average over x, possibly rebin, subtract background on timebin by time bin basis, then integrate over the foreground
	//files will be loaded into root:packages:platypus:data:Reducer:+cleanupname(removeending(fileStr,".nx.hdf"),0)
	
	//OUTPUT
	//M_Spec,M_specSD,M_lambda,M_lambdaSD,M_lambdaHIST,M_specTOF,M_specTOFHIST, W_waternorm, M_beampos
	
	variable toffset, nrebinpnts,ii, jj, pairing, freq, poff, calculated_width, temp, finishingPoint, MASTER_OPENING
	variable originalScanPoint, scanpoint, numTimeSlices, numSpectra, typeOfIntegration, timeSliceDuration
	string tempDF, cDF,tempDFwater, eventStreamingFile, cmd, proccmd, fractionalTimeStr
	variable/c bkgloc
	Wave/z hmmWater
	
	//create the data folder structure
	cDF = getdatafolder(1)
	
	Newdatafolder/o root:packages
	Newdatafolder /o root:packages:platypus
	Newdatafolder /o root:packages:platypus:data
	Newdatafolder /o root:packages:platypus:data:Reducer
	
	if(loLambda <= 0)
		loLambda = 0.1
	endif
	if(hiLambda < loLambda)
		hiLambda = loLambda+1
	endif
	if(paramisdefault(scanpointrange))
		scanpointrange = ""
	endif
	if(paramisdefault(manual))
		manual = 0
	endif
	if(paramisdefault(expected_peak))
		expected_peak = cmplx(ROUGH_BEAM_POSITION, NaN)
	endif
	if(paramisdefault(actual_peak))
		actual_peak = cmplx(NaN, NaN)
	endif
	if(paramisdefault(verbose))
		verbose = 1
	endif
	if(paramisdefault(water))
		water = ""
	endif
	if(paramisdefault(dontoverwrite))
		dontoverwrite = 0
	endif

	
	//figure out if you are doing a directbeam run
	if(paramisdefault(isDirect))
		Doalert 1,"Is "+ filename + " a direct beamrun?"
		if(V_Flag == 1)
			isDirect = 1
		else
			isDirect = 0
		endif
	endif

	try
		//try and load the data
		if(loadNeXUSfile(inputPathStr, filename, outputPathStr = outputpathStr))
			print "problem whilst loading NeXUS file: ",  filename, " (processNexusfile)"
			abort
		endif
		
		//check the data is loaded
		tempDF = "root:packages:platypus:data:Reducer:"+cleanupname(removeending(filename,".nx.hdf"),0)
		if(!datafolderexists(tempDF))
			print "ERROR: you have not loaded ", filename, " (processNexusfile)"
			abort
		endif
		setdatafolder $tempDF
	
		Wave hmm = $(tempDF+":data:hmm")
		Wave hmmcopy = $(tempDF+":instrument:detector:hmm")
		killwaves/z hmmcopy
		
		//figure out if you want to average over many scanpoints
		//scanpoint == -1 means output spectra individually (UNLESS EVENTSTREAMING is specified && scanpoint -finishingpoint == 0)
		//		typeOfIntegration = 2

		//scanpoint = 0, finishingpoint = 2 means sum 0, 1 & 2.:
		//		typeOfIntegration = 0
		
		//if(scanpoint - finishingpoint) == 0, and if the eventstreaming variable is > 0, then we want to parse the event data.
		//		typeOfIntegration = 1


		if(paramisdefault(scanpointrange) && dimsize(hmm, 0) > 1)
			scanpoint = 0
			finishingPoint = dimsize(hmm, 0) - 1
			prompt scanpoint, "startingPoint 0<= scanpoint<="+num2istr(finishingPoint ) 
			prompt finishingPoint, "finishingPoint startingPoint<= scanpoint<="+num2istr(finishingPoint) 

			doprompt filename + ", start and finish points: "+filename, scanpoint, finishingPoint
			if(V_Flag)
				print "DIDN'T WANT TO ENTER A scanpoint (processNexusFile)"
				abort
			endif
			scanpoint = round(scanpoint)
			finishingPoint = round(finishingPoint)
			if(scanpoint < 0)
				scanpoint = 0
			endif
			if(finishingPoint > dimsize(hmm, 0) -1)
				finishingPoint = dimsize(hmm, 0) -1
			endif
		elseif(!paramisdefault(scanpointrange) && strlen(scanpointrange) == 0)
			scanpoint = 0
			finishingPoint = dimsize(hmm, 0) - 1
		elseif(!paramisdefault(scanpointrange) && strlen(scanpointrange) > 0)
			//we expect a range like 1>2 or 5>100
			if(itemsinlist(scanpointrange, ">") == 2)
				scanpoint = str2num(stringfromlist(0, scanpointrange, ">"))
				finishingpoint = str2num(stringfromlist(1, scanpointrange, ">"))
			elseif(itemsinlist(scanpointrange, ">") == 1)//one number
				scanpoint = str2num(scanpointrange)
				finishingpoint = str2num(scanpointrange)
			endif
			scanpoint = round(scanpoint)
			finishingpoint = round(finishingpoint)
			if(numtype(scanpoint) || numtype(finishingpoint) || scanpoint < -1 || scanpoint > dimsize(hmm, 0) -1)
				abort "Incorrect range for scanpoints, specify as 1>100 (processNexusfile)"
			endif
		endif
		
		//some wave definitions
		Wave BM1_counts = $(tempDF+":monitor:bm1_counts")
		Wave frequency = $(tempDF+":instrument:disk_chopper:ch1speed")
		Wave  ss2vg = $(tempDF+":instrument:slits:second:vertical:gap")
		Wave ss3vg = $(tempDF+":instrument:slits:third:vertical:gap")
		Wave sample_distance = $(tempDF+":instrument:parameters:sample_distance")
		Wave slit3_distance = $(tempDF+":instrument:parameters:slit3_distance")
		Wave slit2_distance = $(tempDF+":instrument:parameters:slit2_distance")
		Wave DetectorPos = $(tempDF+":instrument:detector:longitudinal_translation")
		Wave time0 = $(tempDF+":instrument:detector:time0")
		Wave chopper1_distance = $(tempDF+":instrument:parameters:chopper1_distance")
		Wave chopper2_distance = $(tempDF+":instrument:parameters:chopper2_distance")
		Wave chopper3_distance = $(tempDF+":instrument:parameters:chopper3_distance")
		Wave chopper4_distance = $(tempDF+":instrument:parameters:chopper4_distance")
		Wave ch2speed = $(tempDF + ":instrument:disk_chopper:ch2speed")
		Wave ch3speed = $(tempDF + ":instrument:disk_chopper:ch3speed")
		Wave ch4speed = $(tempDF + ":instrument:disk_chopper:ch4speed")
		Wave ch2phase = $(tempDF + ":instrument:disk_chopper:ch2phase")
		Wave ch3phase = $(tempDF + ":instrument:disk_chopper:ch3phase")
		Wave ch4phase = $(tempDF + ":instrument:disk_chopper:ch4phase")
		Wave ch2phaseoffset = $(tempDF + ":instrument:parameters:chopper2_phase_offset")
		Wave ch3phaseoffset = $(tempDF + ":instrument:parameters:chopper3_phase_offset")
		Wave ch4phaseoffset = $(tempDF + ":instrument:parameters:chopper4_phase_offset")
		
		//pre-average the data over x
		if(wavedims(hmm) != 4)
			print "ERROR: dataset must be saved as HISTOGRAM_XYT to be handled correctly (processNexusfile)"
			abort
		endif
		
		//figure out if you want to accumulate over many scanpoints		
		//scanpoint = 0, finishingpoint = 2 means sum 0, 1 & 2.:
		//		typeOfIntegration = 0
		
		//if(scanpoint - finishingpoint) == 0, and if the timeslices wave is specified, then we want to parse the event data.
		//		typeOfIntegration = 1
		
		//scanpoint == -1 means output spectra individually (UNLESS TIMESLICES is specified && scanpoint -finishingpoint == 0)
		//		typeOfIntegration = 2

		if(scanpoint == -1)
			typeOfIntegration = 2
		endif
		if(scanpoint ==  finishingpoint && waveexists(timeSlices) && numpnts(timeslices) > 1)
			typeOfIntegration = 1
		endif
		if(scanpoint == -1 && waveexists(timeSlices) && numpnts(timeslices) > 1 &&  dimsize(hmm, 0) == 1)
			typeOfIntegration = 1
			scanpoint = 0
			finishingpoint = 0
		endif
		if(scanpoint != finishingpoint && scanpoint >= 0)
			typeOfIntegration = 0
		endif

		switch(typeOfIntegration)
			case 0:
				//we want to use the hmm data in the NeXUS file.  This will be the default option probably.
				make/o/d/n=(dimsize(hmm, 1),dimsize(hmm, 2),dimsize(hmm, 3)) detector = 0
				make/o/d/n=1 BM1counts = 0
	
				//you may want to have several scans (within a file) and add over those
				for(ii = scanpoint ; ii < finishingPoint + 1; ii += 1)
					multithread detector[][][] += hmm[ii][p][q][r]
					BM1counts[0] += BM1_counts[ii]
				endfor
				make/o/d/n=(1) dBM1counts = sqrt(BM1counts + 1)

				//Take ntyx and convert to tyn, averaging over x	
				imagetransform sumplanes, detector
				Wave M_sumplanes
				duplicate/o M_sumplanes, detector
				redimension/n=(-1, -1, 1) detector
				duplicate/o detector, detectorSD
				multithread detectorSD = sqrt(detector + 1)
				killwaves/z M_sumplanes, hmm
				numSpectra = 1
			
				break
			case 1:
				Wave/z/t daq_dirname = $(tempDF + ":instrument:detector:daq_dirname")
				if(waveexists(daq_dirname))
					eventStreamingFile = daq_dirname[0]
				else
					prompt eventStreamingFile, "Please enter the directory name of the eventstreaming file"
					eventstreamingfile = "DAQ_" + Secs2Date(DateTime, -2) + "T00-00-00"
					Doprompt "", eventStreamingFile
					if(V_Flag)
						abort
					endif
				endif
				if(Pla_openStreamer(inputPathStr + eventStreamingFile, dataset = scanpoint))
					print "ERROR opening streaming dataset (processNexusfile)"
					abort
				endif
				
				//now histogram the events.
				Wave xbins = $(tempDF+":data:x_bin")
				Wave ybins = $(tempDF+":data:y_bin")
				Wave tbins = $(tempDF+":data:time_of_flight")
				Wave streamedDetector = Pla_streamedDetectorImage(xbins, ybins, tbins, frequency[scanpoint] / 60, timeSlices, round(time0[scanpoint]))
				numtimeslices = dimsize(streamedDetector, 0)	
				fractionalTimeStr = stringbykey("TIME", note(streamedDetector))
				
				make/d/n=(numtimeSlices)/free fractionOfTotalTime
				for(ii = 0 ; ii < numtimeslices ; ii+=1)
//					print str2num(stringfromlist(ii, fractionalTimeStr, ","))
					fractionOfTotalTime[ii] = str2num(stringfromlist(ii, fractionalTimeStr, ","))
				endfor
				
				make/o/d/n=(numTimeSlices) BM1counts
				BM1counts = bm1_counts[scanpoint] * fractionofTotalTime[p]
//				BM1counts[numtimeslices - 1] = bm1_counts[scanpoint] * (fractionalTimeSlices - (ceil(fractionalTimeSlices) - 1)) / fractionalTimeSlices 
				make/o/d/n=(numTimeSlices) dBM1counts = sqrt(BM1counts + 1)
			
				make/o/d/n=(dimsize(tbins, 0) - 1, dimsize(ybins, 0) - 1, numTimeSlices) detector = 0
				for(ii = 0 ; ii < dimsize(streamedDetector, 3) ; ii += 1)
					//convert to tyn, averaging over x
					multithread detector[][][] += streamedDetector[r][p][q][ii]
				endfor
				duplicate/o detector, detectorSD
				multithread detectorSD = sqrt(detector + 1)	
				killdatafolder/z  $("root:packages:platypus:data:Reducer:streamer")
				numSpectra = numTimeSlices
				killwaves/z hmm
				break
			case 2:
				make/o/d/n=(dimsize(hmm, 1),dimsize(hmm, 2), dimsize(hmm, 0)) detector = 0
				make/o/d/n=(dimsize(hmm, 0)) BM1counts = BM1_counts
				make/o/d/n=(dimsize(hmm, 0)) dBM1counts = sqrt(BM1counts + 1)
				//Take ntyx and convert to tyn, averaging over x			
				for(ii = 0 ; ii < dimsize(hmm, 3) ; ii += 1)
					multithread detector[][][] += hmm[r][p][q][ii]
				endfor
				duplicate/o detector, detectorSD
				multithread detectorSD = sqrt(detector + 1)	
				numSpectra = dimsize(hmm, 0)	
				scanpoint = 0
				killwaves/z hmm
				break
		endswitch
		
		Wave BM1counts, dBM1counts
		originalScanPoint = scanpoint

		//check the waterrun is loaded
		if(!paramisdefault(water) && strlen(water) > 0)
			tempDFwater = "root:packages:platypus:data:Reducer:"+cleanupname(removeending(water,".nx.hdf"),0)
			if(!datafolderexists(tempDFwater))
				print "specified water run not already loaded (processNexusfile)"
				abort
			endif
			Wave hmmWater = $(tempDFwater+":data:hmm");AbortonRTE
			if(!waveexists($"root:packages:platypus:data:Reducer:"+cleanupname(removeending(water,".nx.hdf"),0)+":W_waternorm"))
				if(createWaterNormalisationWave(hmmWater, fileName))
					print "ERROR: creating water normalisation array (processNexusfile)"
					abort
				endif
			endif
			Wave W_waternorm = $"root:packages:platypus:data:Reducer:"+cleanupname(removeending(water,".nx.hdf"),0)+":W_waternorm"
			Wave W_waternormSD = $"root:packages:platypus:data:Reducer:"+cleanupname(removeending(water,".nx.hdf"),0)+":W_waternormSD"
			
			if(numpnts(W_Waternorm) != Dimsize(detector, 1))
				print "ERROR: water normalisation run doesn't have the same number of y pixels as the data it is trying to normalise (processNexusfile)"
				abort
			endif
			//divide through by the water normalisation
			for(jj = 0 ; jj < dimsize(detector, 2) ; jj += 1)
				for(ii = 0 ; ii < dimsize(detector, 0) ; ii += 1)
					multithread detectorSD[ii][][jj] = sqrt(((detectorSD[ii][q][jj] / W_waternorm[q])^2 + (detector[ii][q][jj]^2 / (W_waternorm[q]^4)) * W_waternormSD[q]^2))
					multithread detector[ii][][jj] /= W_waternorm[q]					
				endfor
			endfor
		endif
		
		
		//this is where we start on Scanpoints, etc. X.X, but set up some waves beforehand
		
		//setup time of flight paraphenalia
		Wave TOF = $(tempDF + ":data:time_of_flight")
		make/n=(dimsize(TOF, 0), numspectra)/o/d M_specTOFHIST, M_lambdaHIST
		make/n=(dimsize(TOF, 0) - 1, numspectra)/o/d M_lambda, M_specTOF
		make/d/o/n=(numspectra) chod, D_CX, phaseAngle
		M_specTOFHIST[][] = TOF[p][q]
		M_lambdaHIST = 0
		
		//TODO. FOR SOMEREASON THE PARAMETERS IN :instrument:parameters DO NOT GET SAVED IN ARRAY FORM
		//THEREFORE TAKE SCANPOINT 0 AS THE VALUE.  WHEN THIS GETS FIXED GO BACK AND CHANGE IT.
		for(ii = 0 ; ii < numspectra ; ii += 1)
			if(typeOfIntegration == 2 && ii)
				scanpoint += 1
			endif

			//work out the "supposed" omega and two_theta values
			if(paramisdefault(omega))
				Wave W_omega = $(tempDF+":instrument:parameters:omega")
				omega = W_omega[0]
			endif
			if(paramisdefault(two_theta))
				Wave W_two_theta = $(tempDF+":instrument:parameters:twotheta")
				two_theta = W_two_theta[0]
			endif
		
			//setup the default parameters, such as distance, chopper frequency, etc.
			//the phase definitions are as follows:
			//
			// When the PHASE ANGLE=0 then the leading edge of the secondary chopper is aligned with the 
			// trailing edge of the master chopper.
			//
			// The PHASE OFFSET accounts for the fact that the choppers aren't perfectly setup and describes the angular offset required
			// to make the PHASE ANGLE 0.
			//
			//	A POSITIVE phase angle would lead to a phase OPENING, i.e. a direct line of sight.
			//   Hence a POSITIVE phase offset would move the choppers towards a phase opening.
			//  
			//	A NEGATIVE phase angle means that one starts to remove lower wavelengths from the beam.
			//
			//   For example: the nominal phase operation of chopper 3 is 42.5 degrees, with a phase offset of 0.33 degrees.
			//   if one wants a phase opening of 2 degrees one would move the phase
			//    of chopper 3 to 42.5-0.33-2. = 40.17
			//  For a phase closing of 2, move to 42.5-0.33+2 = 44.17
			//  If the phase offset was -0.33 then the first case one changes to 42.5+0.33-2 = 40.83, the second at 44.83.
			// 
			// This applies towards choppers 2 and 3.  It is slightly different for chopper 4.  For this the nominal operating
			// phase is -60 degrees.  A phase opening for this chopper is towards 0.  I.e. For a phase opening of 1 degrees operate at
			// -59 and vice versa.
			//  Thus a positive phase offset for chopper 4, such as 0.23 degrees, one would operate the choppers at -59.79 degrees.  
			// If a phase opening of 2 degrees is required then would operate at -60+0.23+2 = -57.79.
			freq  = abs(frequency[scanpoint] / 60)
			pairing = 0

			//perhaps you've swapped the encoder discs around and you want to use a different pairing
			//there will be slave, master parameters, read the pairing from them.
			//this is because the hardware readout won't match what you actually used.
			//these slave and master parameters need to be set manually.
			if(exists(tempDF + ":instrument:parameters:slave") == 1 && exists(tempDF + ":instrument:parameters:master") == 1)
				Wave slave = $(tempDF+":instrument:parameters:slave")
				Wave master = $(tempDF+":instrument:parameters:master")
				phaseangle[ii] = 0
				if(slave[0] < 1 || slave[0] > 4 || master[0] < 1 || master[0] > 4)
					print "ERROR master/slave pairing is incorrect (processNexusfile)"
					abort
				endif
				pairing = pairing | 2^slave[0]
				pairing = pairing | 2^master[0]
			
				switch (master[scanpoint])
					case 1:
						D_CX[ii] = -chopper1_distance[0]
						phaseangle[ii] += 0.5 * O_C1d
						MASTER_OPENING = O_C1
						break
					case 2:
						D_CX[ii] = -chopper2_distance[0]
						phaseangle[ii] += 0.5 * O_C2d
						MASTER_OPENING = O_C2
						break
					case 3:
						D_CX[ii] = -chopper3_distance[0]
						phaseangle[ii] += 0.5 * O_C3d
						MASTER_OPENING = O_C3
						break
					default:
						print "ERROR master/slave pairing is incorrect (processNexusfile)"
						break
				endswitch			
				switch (slave[scanpoint])
					case 2:
						D_CX[ii] += chopper2_distance[0]
						phaseangle[ii] += 0.5 * O_C2d
						phaseangle[ii] += -ch2phase[0] - ch2phaseoffset[0]
						break
					case 3:
						phaseangle[ii] += 0.5 * O_C3d
						phaseangle[ii] += -ch3phase[0] - ch3phaseoffset[0]
						D_CX[ii] += chopper3_distance[0]
						break
					case 4:
						phaseangle[ii] += 0.5 * O_C4d
						phaseangle[ii] += ch4phase[0] - ch4phaseoffset[0]
						D_CX[ii] += chopper4_distance[0]
						break
					default:
						print "ERROR master/slave pairing is incorrect (processNexusfile)"
						break
				endswitch			
			else
				//the slave and master parameters don't exist, work out the pairing assuming 1 is the master disk.
				pairing = pairing | 2^1
				MASTER_OPENING = O_C1
				if(abs(ch2speed[0]) > 10)
					pairing = pairing | 2^2
					D_CX[ii] = chopper2_distance[0]
					phaseangle[ii] = -ch2phase[0] - ch2phaseoffset[0] + 0.5*(O_C2d+O_C1d)
				elseif(abs(ch3speed[scanpoint]) > 10)
					pairing = pairing | 2^3
					D_CX[ii] = chopper3_distance[0]
					phaseangle[ii] = -ch3phase[0] - ch3phaseoffset[0] + 0.5*(O_C3d+O_C1d)
				else
					pairing = pairing | 2^4
					D_CX[ii] = chopper4_distance[0]
					phaseangle[ii] = ch4phase[0] - ch4phaseoffset[0] + 0.5*(O_C4d + O_C1d)
				endif
			endif
		
			//work out the total flight length
			chod[ii] = ChoDCalculator(fileName, omega, two_theta, pairing = pairing, scanpoint = 0)
			if(numtype(chod[ii]))
				print "ERROR, chod is NaN (processNexusdata)"
				abort
			endif
				
			//toffset - the time difference between the magnet pickup on the choppers (TTL pulse), which is situated in the middle of the chopper window, and the trailing edge of chopper 1, which 
			//is supposed to be time0.  However, if there is a phase opening this time offset has to be relocated slightly, as time0 is not at the trailing edge.
			if(exists(tempDF + ":instrument:parameters:chopper1_phase_offset") == 1)
				Wave ch1phaseoffset = $(tempDF + ":instrument:parameters:chopper1_phase_offset")
				poff = ch1phaseoffset[0]
			else
				print "ERROR chopper1_phase_offset not specified"
				abort
			endif
			variable poffset = 1e6 * poff/(2 * 360 * freq)
			toffset = poffset + (1e6 * MASTER_OPENING/2/(2 * Pi)/freq) - (1e6 * phaseAngle[ii] /(360 * 2 * freq))
			Multithread M_specTOFHIST[][ii] -= toffset
		
			//		print master, slave, chod, phaseangle, poff, toffset
		endfor
			
		//convert TOF to lambda	
		Multithread M_lambdaHIST[][] = TOFtoLambda(M_specTOFHIST[p][q], ChoD[q])
		M_lambda[][] = 0.5* (M_lambdaHIST[p][q] + M_lambdaHIST[p + 1][q])
		
		//find out where the beam hits the detector
		//this will be done on an average of the entire detector image
		//work out what the total expected width of the beam is first
		//from De Haan1995
		if(paramisdefault(actual_peak) || numtype(imag(actual_peak)) || numtype(real(actual_peak)))
			calculated_width = 2 * (ss3vg[scanpoint]/2 + ((ss2vg[scanpoint] + ss3vg[scanpoint])*(detectorpos[scanpoint]+sample_distance[0]-slit3_distance[0])/(2*(slit3_distance[0]-slit2_distance[0])))) / Y_PIXEL_SPACING
			expected_peak = cmplx(real(expected_peak), 2.5* calculated_width +2)
			
			if(manual || findspecridge(detector, 50, 0.01, expected_peak, binarysearch(M_lambda, hilambda), actual_peak) || numtype(real(actual_peak)) || numtype(imag(actual_peak)))
				//use the following procedure to find the specular ridge
				userSpecifiedArea(detector, actual_peak, bkgloc)
				Waveclear backgroundMask
				make/d/free/n=(dimsize(detector, 1)) bkgregion = NaN
				Wave backgroundMask = bkgregion
				backgroundMask = (p >= floor(real(bkgloc)) && p < (floor(real(actual_peak) - 0.5 * (INTEGRATEFACTOR * imag(actual_peak))) - BACKGROUNDOFFSET - 1)) ? 1: backgroundMask[p]
				backgroundMask = (p <= ceil(imag(bkgloc)) && p > (ceil(real(actual_peak) + 0.5 * (INTEGRATEFACTOR * imag(actual_peak))) + BACKGROUNDOFFSET + 1)) ? 1: backgroundMask[p]
				
				//			imagetransform sumallcols detector
				//			duplicate/o W_sumcols, xx
				//			xx = p
				//			peak_params = cmplx(Pla_peakcentroid(xx,W_sumcols),expected_width)

				//			peak_params = cmplx(expected_centre, calculated_width)
				killwaves/z W_sumcols,xx
			endif
		endif
					
		//if you are a direct beam do a gravity correction, but have to recalculate centre.
		if(isDirect)
			variable lobin = (real(actual_peak)-4 - 1.3 * imag(actual_peak) / 2) , hiBin = (real(actual_peak) + 4 + 1.3 * imag(actual_peak) / 2)
			correct_for_gravity(detector, detectorSD, M_lambda, 0, loLambda, hiLambda, lobin, hiBin)
			Wave M_gravitycorrected, M_gravitycorrectedSD

			detector[][][] = M_gravityCorrected[p][q][r]
			detectorSD[][][] = M_gravityCorrectedSD[p][q][r]

			killwaves/z M_gravitycorrected, M_gravitycorrectedSD
			if(findspecridge(detector, 50, 0.01, expected_peak, dimsize(detector, 0), actual_peak) || numtype(real(actual_peak)) || numtype(imag(actual_peak)))
				//use the following procedure to find the specular ridge
				userSpecifiedArea(detector, actual_peak, bkgloc)
				Waveclear backgroundMask
				make/d/free/n=(dimsize(detector, 1)) bkgregion = NaN
				Wave backgroundMask = bkgregion
				backgroundMask = (p >= floor(real(bkgloc)) && p < (floor(real(actual_peak) - 0.5 * (INTEGRATEFACTOR * imag(actual_peak))) - BACKGROUNDOFFSET - 1)) ? 1: backgroundMask[p]
				backgroundMask = (p <= ceil(imag(bkgloc)) && p > (ceil(real(actual_peak) + 0.5 * (INTEGRATEFACTOR * imag(actual_peak))) + BACKGROUNDOFFSET + 1)) ? 1: backgroundMask[p]
			endif	
		endif

		scanpoint = originalScanPoint
			
		//someone provided a wavelength spectrum BIN EDGES to rebin to.
		variable hiPoint, loPoint
		if(!paramisdefault(rebinning) && waveexists(rebinning))
//			loPoint = binarysearch(rebinning, loLambda)
//			hiPoint = binarySearch(rebinning, hiLambda)
//			if(0 <= hiPoint)
//				deletepoints hiPoint+1, numpnts(rebinning), rebinning		
//			endif
//			if(0 <= loPoint)
//				deletepoints 0, loPoint + 1, rebinning
//			endif
				
			//rebin detector image, this is layer capable
			if(Pla_PlaneIntRebin(M_lambdaHIST, detector, detectorSD, rebinning))
				print "ERROR while rebinning detector pattern (processNexusfile)"
				abort
			endif
			Wave M_rebin, M_rebinSD
			duplicate/o M_rebin,  $(tempDF+":detector")
			duplicate/o M_rebinSD,  $(tempDF+":detectorSD")
			Wave detector, detectorSD
			
			redimension/n=(dimsize(rebinning, 0), -1) M_lambdaHIST, M_specTOFHIST
			M_lambdaHIST[][] = rebinning[p][q]			
			Multithread M_specTOFHIST[][] = LambdatoTOF(M_lambdaHIST[p][q], chod[q])			
			killwaves/z W_tof, M_rebin, M_rebinSD
			
		else		//delete the lolambda and hilambda cutoffs
			imagetransform/g=0 getcol M_lambdaHIST
			Wave W_extractedCol
			loPoint = binarysearch(W_extractedCol, loLambda)
			hiPoint = binarySearch(W_extractedCol, hiLambda)
			if(0 <= hiPoint && hiPoint < dimsize(M_lambdaHIST, 0))
				//these are histogram bins
				deletepoints/M=0 hiPoint+1, dimsize(M_lambdaHIST, 0), M_lambdaHIST, M_specTOFHIST		
				//these aren't
				deletepoints/M=0 hiPoint, dimsize(M_lambdaHIST, 0), detector, detectorSD
			endif
			if(0 <= loPoint)
				deletepoints/M=0 0, loPoint+1, M_lambdaHIST, detector, detectorSD, M_specTOFHIST
			endif
			Killwaves/z W_extractedCol	
		endif
		
		//convert histogrammed TOF and lambda to their point counterparts
		redimension/n=(dimsize(M_lambdaHIST, 0) - 1, - 1) M_lambda, M_spectof
		M_lambda[][] = 0.5 * (M_lambdaHIST[p][q] + M_lambdaHIST[p + 1][q])
		M_spectof[][] = 0.5 * (M_specTOFHIST[p][q] + M_specTOFHIST[p + 1][q])
		
		//multiply by the bin width so we can compare spectra between different rebinnings.
		detector[][][] /= M_lambdaHIST[p+1][r] - M_lambdaHIST[p][r]
		detectorSD[][][] /= M_lambdaHIST[p+1][r] - M_lambdaHIST[p][r]

		//Now work out where the beam hits the detector
		//this is used to work out the correct angle of incidence.
		//it will be contained in a wave called beampos
		//beampos varies as a fn of wavelength due to gravity

		if(isDirect)
			//the spectral ridge for the direct beam has a gravity correction involved with it.
			//the correction coefficients for the beamposition are contaned in M_gravCorrCoefs
			Wave M_gravCorrCoefs = $(tempDF+":M_gravCorrCoefs")
			duplicate/o M_lambda, $(tempDF+":M_beampos")
			Wave M_beampos = $(tempDF+":M_beampos")
			
//			for(ii = 0 ; ii < numspectra ; ii += 1)
//				imagetransform/g=(ii) getcol M_gravCorrCoefs
//				Wave W_extractedCol
//				M_beampos[][ii] = deflec(W_extractedCol, M_lambda[p][ii])	
//			endfor
//			Killwaves/z W_extractedCol

			//the following correction assumes that the directbeam neutrons are falling from a point position W_gravCorrCoefs[0] before the detector
			//At the sample stage (W_gravcorrcoefs[0] - detectorpos[0]) they have a certain vertical velocity, assuming that the neutrons had an initial vertical velocity of 0
			// Although the motion past the sample stage will be parabolic, assume that the neutrons travel in a straight line after that (i.e. the tangent of the parabolic motion at the sample stage)
			// this should give an idea of the direction of the true incident beam, as experienced by the sample
			//Factor of 2 is out the front to give an estimation of the increase in 2theta of the reflected beam.
			scanpoint = originalScanPoint
			for(ii = 0 ; ii < numspectra ; ii += 1)
				if(typeOfIntegration == 2)
					scanpoint += 1
				endif
				M_beampos[][ii] = M_gravCorrCoefs[1][ii] -2 * ((1/Y_PIXEL_SPACING) * 1000 * 9.81 * ((M_gravCorrCoefs[0][ii] - detectorPos[ii])/1000) * (detectorPos[ii]/1000) * M_lambda[p][ii]^2/((P_MN*1e10)^2))
			endfor
			M_beampos *=  Y_PIXEL_SPACING
		else
			make/o/n=(dimsize(M_lambda, 0), dimsize(M_lambda, 1)) $(tempDF+":M_beampos")
			Wave M_beampos = $(tempDF+":M_beampos")
			M_beampos = (real(actual_peak) * Y_PIXEL_SPACING)
		endif
	
		//this does the background subtraction and integration.  The beam position is ASSUMED NOT TO MOVE
		//during each slice of the detector image.  If it does, then the beam position will have to be 
		//checked for each slice of the detector image
		if(topAndTail(detector, detectorSD, real(actual_peak), imag(actual_peak), background, backgroundMask = backgroundMask))
			print "ERROR while topandtailing (processNexusdata)"
			abort
		endif			
		
		//the output from the topAndTail process is the background subtracted spectrum, etc.
		duplicate/o root:packages:platypus:data:Reducer:M_spec , $(tempDF+":M_spec")
		duplicate/o root:packages:platypus:data:Reducer:M_specSD , $(tempDF+":M_specSD")
		duplicate/o root:packages:platypus:data:Reducer:M_topAndTail , $(tempDF+":M_topAndTail")
		duplicate/o root:packages:platypus:data:Reducer:M_topAndTailSD , $(tempDF+":M_topAndTailSD")
		killwaves/z  root:packages:platypus:data:Reducer:M_topAndTail, root:packages:platypus:data:Reducer:M_topAndTailSD
		
		Wave M_spec = $(tempDF+":M_spec")
		Wave M_specSD = $(tempDF+":M_specSD")
		Wave M_topAndTail = $(tempDF+":M_topandtail")
		Wave M_topAndTailSD = $(tempDF+":M_topandtailSD")
	
		//assert that in the background subtracted specta + SD matrices there are no NaN or SD < 0
		wavestats/q/z M_topandtail
		if(V_numNans || V_numINFs)
			abort "Error, found NaNs or INFs, or there was a negative value in M_topandtail (processNexusFile)"
		endif
		wavestats/q/z M_topandtailSD
		if(V_numNans || V_numINFs || V_min < 0)
			abort "Error, found NaNs or INFs, or there was a negative value in M_topandtailSD (processNexusFile)"
		endif
		wavestats/q/z M_spec
		if(V_numNans || V_numINFs)
			abort "Error, found NaNs or INFs in M_spec (processNexusFile)"
		endif
		wavestats/q/z M_specSD
		if(V_numNans || V_numINFs || V_min < 0)
			abort "Error, found NaNs or INFs, or there was a negative value in M_specSD (processNexusFile)"
		endif


		
		//if you want to normalise by monitor counts do so here.
		//propagate the errors.
		if(!paramisdefault(normalise) && normalise)
			multithread M_specSD[][] = sqrt(((M_specSD[p][q] / BM1counts[q])^2 + (M_spec[p][q]^2 / (BM1counts[q]^4)) * dBM1counts[q]^2))
			multithread M_spec[][] /= BM1counts[q]
			
			multithread M_topandtailSD[][][] = sqrt(((M_topandtailSD[p][q][r] / BM1counts[r])^2 + (M_topandtail[p][q][r]^2 / (BM1counts[r]^4)) * dBM1counts[r]^2))
			multithread M_topandtail[][][] = M_topandtail[p][q][r] / BM1counts[r]
		endif
		
		
		
		//now work out dlambda/lambda, the resolution contribution from wavelength.
		//vanWell, Physica B,  357(2005) pp204-207), eqn 4.
		//this is only an approximation for our instrument, as the 2nd and 3rd discs have smaller
		//openings compared to the master chopper.  Therefore the burst time needs to be looked at.
		//W_point should still be the point version of the TOFhistogram.
		duplicate/o M_lambda, $(tempDF+":M_lambdaSD")
		wave M_lambdaSD = $(tempDF+":M_lambdaSD")
		//account for the width of the time bin
		M_LambdaSD[][] = ((M_specTOFHIST[p+1][q] - M_specTOFHIST[p][q])/(M_specTOF[p][q]))^2
		//account for the gross resolution of the chopper, adding in a contribution if you have a phase
		//opening.  (don't forget freq is in Hz, W_point is in us.
		//TODO ChoD might change from scanpoint to scanpoint..... The resolution will be out if you are scanning dy.
		M_LambdaSD[][] += ((D_CX[q] / ChoD[q])+(phaseAngle[q] / (360 * freq * 1e-6 * M_specTOF[p][q])))^2
		
		//TODO ss2vg might change from scanpoint to scanpoint..... The resolution will be out if you are scanning ss2vg.
		variable tauH = (1e6 * ss2vg[originalscanpoint] / (DISCRADIUS * 2 * Pi * freq))
		M_LambdaSD[][] += (tauH / (M_specTOF[p][q]))^2
		M_LambdaSD *= 0.68^2
		M_lambdaSD = sqrt(M_LambdaSD)
		M_lambdaSD *= M_lambda
	
		if(verbose)
			if(waveexists(rebinning))
				cmd = "processNeXUSfile(\"%s\", \"%s\", \"%s\", %d, %g, %g, water=\"%s\", scanpointrange=\"%s\",eventstreaming=%s,isdirect=%d, expected_peak=cmplx(%g,%g), omega=%g,two_theta=%g,manual=%d, savespectrum=%d, rebinning=%s, normalise=%d,verbose=%d)"
				sprintf proccmd, cmd, inputPathStr, outputPathStr, filename, background, loLambda, hiLambda, water, scanpointrange, nameofwave(timeslices), isDirect, real(expected_peak), imag(expected_peak), omega, two_theta,manual, saveSpectrum, GetWavesDataFolder(rebinning, 2 ), normalise,verbose
			else
				cmd = "processNeXUSfile(\"%s\", \"%s\", \"%s\", %d, %g, %g, water=\"%s\", scanpointrange=\"%s\",eventstreaming=%s,isdirect=%d,  expected_peak=cmplx(%g,%g), omega=%g,two_theta=%g,manual=%d, savespectrum=%d, normalise=%d,verbose=%d)"
				sprintf proccmd, cmd, inputPathStr, outputPathStr, filename, background, loLambda, hiLambda, water, scanpointrange, nameofwave(timeslices), isDirect,real(expected_peak), imag(expected_peak), omega, two_theta,manual, saveSpectrum, normalise,verbose		
			endif
			print proccmd
		endif
		
		//you may want to save the spectrum to file
		if(!paramisdefault(saveSpectrum) && saveSpectrum)
			if(writeSpectrum(outputPathStr, filename, filename, M_spec, M_specSD, M_lambda, M_lambdaSD, proccmd, dontoverwrite=dontoverwrite))
				print "ERROR whilst writing spectrum to file (processNexusfile)"
			endif
		endif
	
		killwaves/z W_point, detector, detectorSD
		setdatafolder $cDF
		
		return 0
	catch
	
		if(verbose)
			if(!paramisdefault(rebinning) && waveexists(rebinning))
				cmd = "processNeXUSfile(\"%s\", \"%s\", \"%s\", %d, %g, %g, water=\"%s\", scanpointrange=\"%s\",timeslices=%s,isdirect=%d, expected_peak=cmplx(%g,%g), omega=%g,two_theta=%g,manual=%d, savespectrum=%d, rebinning=%s, normalise=%d,verbose=%d)"
				sprintf proccmd, cmd, inputPathStr, outputPathStr, filename, background, loLambda, hiLambda, water, scanpointrange, nameofwave(timeslices),isDirect, real(expected_peak), imag(expected_peak), omega, two_theta,manual, saveSpectrum, GetWavesDataFolder(rebinning, 2 ), normalise,verbose
			else
				cmd = "processNeXUSfile(\"%s\", \"%s\", \"%s\", %d, %g, %g, water=\"%s\", scanpointrange=\"%s\",timeslices=%s,isdirect=%d,expected_peak=cmplx(%g,%g), omega=%g,two_theta=%g,manual=%d, savespectrum=%d, normalise=%d,verbose=%d)"
				sprintf proccmd, cmd, inputPathStr, outputPathStr, filename, background, loLambda, hiLambda, water, scanpointrange, nameofwave(timeslices),isDirect, real(expected_peak), imag(expected_peak), omega, two_theta,manual, saveSpectrum, normalise,verbose		
			endif
			print proccmd
		endif
		killwaves/z W_point, detector, detectorSD
		setdatafolder $cDF
		return 1
	endtry
End

Function writeSpectrum(outputPathStr, fname, runnumber, II, dI, lambda, dlambda, reductionnote,[ dontoverwrite])
	String outputPathStr, fname, runnumber
	Wave II, dI, lambda, dlambda
	string reductionnote
	variable dontoverwrite
	//a function to save a spectrum file to disc.
	//pathname = string containing the path to where the data needs to be saved.
	//fname = the filename of the the file you want to write
	//runnumber = the runnumber of the file
	//II = the wave containing the intensities
	//dI = the uncertainty in the intensities (SD)
	//lambda = the wavelength (A)
	//dlambda = the uncertainty in wavelength (FWHM)
	variable fileID, kk
	string data = "", uniquefName
	
	if(paramisdefault(dontoverwrite))
		dontoverwrite = 1
	endif
	
	GetFileFolderInfo/q/z outputPathStr
	if(V_flag)//path doesn't exist
		print "ERROR please give valid path (writeSpectrum)"
		return 1	
	endif
	
	for(kk = 0 ; kk < dimsize(II, 1) ; kk += 1)
		uniquefName = uniqueFileName(outputPathStr, fname, ".spectrum", dontoverwrite = dontoverwrite)
		
		fileID = XMLcreatefile(outputPathStr + uniquefName + ".spectrum", "REFroot", "", "")
		
		if(fileID < 1)
			print "ERROR couldn't create XML file (writeSpecRefXML1D)"
			return 1
		endif
	
		xmladdnode(fileID,"//REFroot","","REFentry","",1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]","","time",Secs2Date(DateTime, 0) + " "+Secs2Time(DateTime, 3))

		xmladdnode(fileID,"//REFroot/REFentry[1]","","Title","",1)

		xmladdnode(fileID,"//REFroot/REFentry[1]","","REFdata","",1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","axes","lambda")
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","rank","1")
	
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","type","POINT")
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","spin","UNPOLARISED")
	
		xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","Run","",1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run[1]","","filename", runnumber +".nx.hdf")
	
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","dim", num2istr(dimsize(II, 0)))
		
		xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(1)+"]","","reductionnote",reductionnote,1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(1)+"]/reductionnote[1]","","software","SLIM")
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(1)+"]/reductionnote[1]","","version", num2istr(Pla_getVersion()))
		
		imagetransform/g=(kk) getCol II
		Wave W_extractedCol
		sockitWaveToString/TXT W_extractedCol, data	
		xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","R", data,1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/R","","uncertainty","dR")

		imagetransform/g=(kk) getCol lambda
		Wave W_extractedCol
		sockitWaveToString/TXT W_extractedCol, data	
		xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata", "", "lambda", data,1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/lambda", "","uncertainty","dlambda")
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/lambda","","units","A")

		imagetransform/g=(kk) getCol dI
		Wave W_extractedCol
		sockitWaveToString/TXT W_extractedCol, data	
		xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","dR", data,1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/dR","","type","SD")

		imagetransform/g=(kk) getCol dlambda
		Wave W_extractedCol
		sockitWaveToString/TXT W_extractedCol, data	
		xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","dlambda", data,1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/dlambda","","type","FWHM")
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/dlambda","","units","A")

		xmlclosefile(fileID,1)
	endfor
	Killwaves/z W_extractedCol
End

Function writeSpecRefH5_1D(outputPathStr, fname, qq, RR, dR, dQ, [resolutionkernel])
	String outputPathStr, fname
	wave qq, RR, dR, dQ
	Wave/z resolutionkernel
	
	variable fileID
	
	try
		hdf5createFile/z/o fileID as outputPathStr + fname + ".h5"
		hdf5savedata  qq, fileID, "Q"
		hdf5savedata RR, fileID, "R"
		hdf5savedata dR, fileID, "E"
		hdf5savedata dq, fileID, "dq"
		if(!paramisdefault(resolutionkernel) && waveexists(resolutionkernel))
			hdf5savedata resolutionkernel, fileID, "resolutionkernel"
		endif
	catch
	endtry
	HDF5closefile/z fileID
End

Function writeSpecRefXML1D(outputPathStr, fname, qq, RR, dR, dQ, exptitle, user, samplename, runnumbers, rednnote)
	String outputPathStr, fname
	wave qq, RR, dR, dQ
	String exptitle, user, samplename, runnumbers, rednnote	//a function to write an XML description of the reduced dataset.
	//pathname is a folder path, e.g. faffmatic:Users:andrew:Desktop: 	REQUIRED
	//fname is the filename of the file you want to write					REQUIRED
	//qq, RR, dR, dQ are the waves you want to write to the file			REQUIRED	
	//exptitle is the experiment title, e.g. "polymer films.				OPTIONAL
	//user is the user name												OPTIONAL
	//samplename is the name of the sample, duh						OPTIONAL
	//runnumbers is a semicolon separated list of the runnumbers making up this file, e.g. PLP0001000;PLP0001001;PLP0001002	OPTIONAL
	//rednnote is the command that was used to do the reduction			OPTIONAL
	
	variable fileID,ii,jj
	string qqStr="",RRstr="",dRStr="", dqStr = "", prefix = ""
	
	GetFileFolderInfo/q/z outputPathStr
	if(V_flag)//path doesn't exist
		print "ERROR please give valid path (writeSpecRefXML1D)"
		return 1	
	endif
		
	//create the XMLfile
	fileID = XMLcreatefile(outputPathStr + fname + ".xml", "REFroot", "", "")
	if(fileID < 1)
		print "ERROR couldn't create XML file (writeSpecRefXML1D)"
	endif

	xmladdnode(fileID,"//REFroot","","REFentry","",1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]","","time",Secs2Date(DateTime,0) + " "+Secs2Time(DateTime,3))

	xmladdnode(fileID,"//REFroot/REFentry[1]","","Title","",1)
	
	//username
	xmladdnode(fileID,"//REFroot/REFentry[1]","","User",user,1)

	//sample names
	xmladdnode(fileID,"//REFroot/REFentry[1]","","REFsample","",1)
	xmladdnode(fileID,"//REFroot/REFentry[1]/REFsample","","ID", samplename,1)

	xmladdnode(fileID,"//REFroot/REFentry[1]","","REFdata","",1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","axes","Qz")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","rank","1")

	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","type","POINT")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","spin","UNPOLARISED")
	
	for(ii=0;ii<itemsinlist(runnumbers);ii+=1)
		xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","Run","",1)
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(ii+1)+"]","","filename",stringfromlist(ii,runnumbers)+".nx.hdf")
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(ii+1)+"]","","preset","")
		XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(ii+1)+"]","","size","")
	endfor
	
	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(1)+"]","","reductionnote",rednnote,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(1)+"]/reductionnote[1]","","software","SLIM")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run["+num2istr(1)+"]/reductionnote[1]","","version", num2istr(Pla_getVersion()))
	
	//create ASCII representation of data
	sockitWaveToString/TXT qq, qqStr
	sockitWaveToString/TXT RR, RRStr
	sockitWaveToString/TXT dR, dRStr
	sockitWaveToString/TXT dQ, dqStr

	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","dim",num2istr(itemsinlist(RRstr," ")))

	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","R",RRStr,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/R","","uncertainty","dR")

	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","Qz",qqStr,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Qz","","uncertainty","dQz")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Qz","","units","1/A")

	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","dR",dRStr,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/dR","","type","SD")

	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","dQz",dqStr,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/dQz","","type","FWHM")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/dQz","","units","1/A")

	xmlclosefile(fileID,1)
End

Function	 write2DXML(outputPathStr, fname, qz2d, qy2d, RR2d, EE2d, exptitle, user, samplename, runnumbers, rednnote)
	String outputPathStr, fname
	wave qz2d, qy2d, RR2d, EE2d
	String exptitle, user, samplename, runnumbers, rednnote
	
	//a function to write an XML description of the reduced dataset.
	variable fileID,ii,jj, numspectra
	string df = "root:packages:platypus:data:Reducer:"
	string qzStr = "", RRstr = "", dRStr = "", qyStr = "", filename, prefix = ""
	
	GetFileFolderInfo/q/z outputPathStr
	if(V_flag)//path doesn't exist
		print "ERROR please give valid path (write2Dxml)"
		return 1	
	endif
	
	fileID = XMLcreatefile(outputPathStr + fname + ".xml", "REFroot", "", "")

	xmladdnode(fileID,"//REFroot","","REFentry","",1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]","","time",Secs2Date(DateTime,0) + " "+Secs2Time(DateTime,3))

	xmladdnode(fileID,"//REFroot/REFentry[1]","","Title","",1)

	xmladdnode(fileID,"//REFroot/REFentry[1]","","User",user,1)

	xmladdnode(fileID,"//REFroot/REFentry[1]","","REFsample","",1)
	xmladdnode(fileID,"//REFroot/REFentry[1]/REFsample","","ID", samplename, 1)

	xmladdnode(fileID,"//REFroot/REFentry[1]","","REFdata","",1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","axes","Qz;Qy")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","rank","2")

	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","type","POINT")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata","","spin","UNPOLARISED")
	
	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","Run","",1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run[1]","","filename",stringfromlist(0,runnumbers)+".nx.hdf")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run[1]","","preset","")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Run[1]","","size","")
	
	SVAR reductionCmd = $(df + stringfromlist(ii , runnumbers) + ":reductionCmd")
	xmladdnode(fileID, "//REFroot/REFentry[1]/REFdata/Run[1]", "", "reductionnote", reductionCmd, 1)
	XMLsetattr(fileID, "//REFroot/REFentry[1]/REFdata/Run[1]/reductionnote[1]", "", "software", "SLIM")

	sockitwavetostring/TXT qz2d, qzStr
	sockitwavetostring/TXT RR2d, RRStr
	sockitwavetostring/TXT qy2d, qyStr
	sockitwavetostring/TXT EE2d, dRStr
	
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata", "", "dim", num2istr(dimsize(RR2d, 0)) + ";" + num2istr(dimsize(RR2d, 1)))

	xmladdnode(fileID, "//REFroot/REFentry[1]/REFdata","","R", RRStr, 1)
	XMLsetattr(fileID, "//REFroot/REFentry[1]/REFdata/R","","uncertainty","dR")

	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","Qz",qzStr,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Qz","","uncertainty","")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Qz","","units","1/A")

	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","Qy",qyStr,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Qy","","uncertainty","")
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/Qy","","units","1/A")

	xmladdnode(fileID,"//REFroot/REFentry[1]/REFdata","","dR",dRStr,1)
	XMLsetattr(fileID,"//REFroot/REFentry[1]/REFdata/dR","","type","SD")

	xmlclosefile(fileID, 1)
	
End


Function madd(inputPathStr, filenames)
	string inputPathStr, filenames

	variable ii,jj, kk, fileIDadd, fileIDcurrent, err=0
	string nodes = "",temp, addfile, cDF, nodename, attributes

	cDF = getdatafolder(1)
	newdatafolder/o root:packages
	newdatafolder/o root:packages:platypus
	newdatafolder/o/s $"root:packages:platypus:temp"

	GetFileFolderInfo/q/z inputPathStr
	if(V_flag)//path doesn't exist
		print "ERROR please give valid path (madd)"
		return 1	
	endif

	//nodes += "/entry1/data/hmm;"
	//nodes += "/entry1/data/time;"
	//nodes += "/entry1/data/total_counts;"
	nodes +=  "/entry1/instrument/detector/hmm;"
	nodes += "/entry1/instrument/detector/total_counts;"
	nodes += "/entry1/instrument/detector/time;"
	nodes += "/entry1/monitor/bm1_time;"
	nodes += "/entry1/monitor/bm1_counts;"
	nodes += "/entry1/monitor/bm2_counts;"
	nodes += "/entry1/monitor/bm2_time;"
	nodes += "/entry1/monitor/time"

	try
		for(ii=0 ; ii<itemsinlist(filenames); ii+=1)
			temp = removeending( stringfromlist(ii,filenames), ".nx.hdf")+".nx.hdf"
			if(!doesnexusfileexist(inputPathStr, temp))
				print "ERROR one of the filenames doesn't exist (madd)";abort	
			endif
		endfor

		temp = removeending( stringfromlist(0, filenames), ".nx.hdf")+".nx.hdf"
		copyfile/o inputPathStr+temp as inputPathStr+"ADD_"+temp
		if(V_Flag)
			print "ERROR copying file failed (madd)";abort
		endif

		addfile = inputPathStr + "ADD_"+temp

		hdf5openfile/Z fileIDadd as addfile
		if(V_Flag)
			print "ERROR opening add file (madd)";abort
		endif

		for(ii=1 ; ii<itemsinlist(filenames) ; ii+=1)
			temp = removeending( stringfromlist(ii,filenames), ".nx.hdf")+".nx.hdf"
			hdf5openfile/R/Z fileIDcurrent as inputPathStr + temp
			if(V_Flag)
				print "ERROR opening add file (madd)";abort
			endif
			//now copy the nodes
			for(jj=0 ; jj<itemsinlist(nodes) ; jj+=1)
				attributes = ""
				nodename = stringfromlist(jj, nodes)
				
				hdf5loaddata/q/z fileIDadd, nodename
				if(V_Flag)
					print "ERROR while loading a dataset (madd)";abort
				endif
				Wave numwave1 = $stringfromlist(0, S_Wavenames)
				hdf5loaddata/q/z fileIDcurrent, nodename
				if(V_Flag)
					print "ERROR while loading a dataset (madd)";abort
				endif
				Wave numwave2 = $stringfromlist(0, S_Wavenames)
				numwave1 = numwave1+numwave2

				make/o/d/n=(wavedims(numwave1),4) hyperslab
				hyperslab[][0] = 0
				hyperslab[][1] = 1
				hyperslab[][2] = 1
				hyperslab[][3] = dimsize(numwave1, p)
				///gzip={6,0}/LAYO={2,dimsize(numwave1,0),dimsize(numwave1,1),dimsize(numwave1,2),dimsize(numwave1,3)} 
				
				hdf5savedata/o/z/slab=hyperslab numwave1, fileIDadd, nodename
				if(V_Flag)
					print "ERROR couldn't save added data to ADD file (madd)";abort
				endif

				killwaves/a/z
			endfor
	
			hdf5closefile/Z fileIDcurrent
			if(V_Flag)
				print "ERROR couldn't close current file (madd)";abort
			endif
		endfor

		hdf5closefile/z fileIDadd
		if(V_Flag)
			print "ERROR couldn't close ADD file (madd)";	abort
		endif

	catch
		err = 1
		hdf5closefile/z fileIDadd
		hdf5closefile/z fileIDcurrent
	endtry

	setdatafolder $cDF
	killdatafolder/z $"root:packages:platypus:temp"
	return err
End

Function delReducedPoints()
	variable theFile
	Open/R/D/M="Please select the h5 file to remove points from."/T=".h5" theFile
	if(strlen(S_filename) > 0)
		string inputPathStr = ParseFilePath(1, S_filename, ":", 1, 0)
		string fileInStr = ParseFilePath(0, S_filename, ":", 1, 0)
		string pointsToDelete = ""
		prompt pointsToDelete, ""
		string help = "Please enter individual points numbers, or ranges.  A typical string is \"0; 20-31\" which would delete point 0 and points 20 to 31"
		Doprompt/help = help "Enter the points to delete", pointsToDelete
		if(!V_flag)
			delrefpoints(inputPathStr, fileInStr, pointsToDelete)
		endif
	endif
End

Function delrefpoints(inputPathStr, filename, pointlist)
	string inputPathStr, filename, pointlist

	string data,temp
	variable fileID,ii, numtoremove, lower, upper

	try
		hdf5openfile fileID as inputPathStr + filename + ".h5"
		pointlist = sortlist(pointlist, ";", 3)
		pointlist = lowerstr(pointlist)
		if(grepstring(pointlist, "[a-z]+"))
			print "ERROR list of points should only contain numbers";abort
		endif
		
		hdf5loaddata/z/o/q fileID, "R"
		Wave RR = $(stringfromlist(0, S_wavenames))
		
		hdf5loaddata/z/o/q fileID, "Q"
		Wave qq = $(stringfromlist(0, S_wavenames))
		
		hdf5loaddata/z/o/q fileID, "E"
		Wave EE = $(stringfromlist(0, S_wavenames))

		hdf5loaddata/z/o/q fileID, "dq"
		Wave dq = $(stringfromlist(0, S_wavenames))

		hdf5loaddata/z/o/q fileID, "resolutionkernel"
		Wave resolutionkernel = $(stringfromlist(0, S_wavenames))
		
		for(ii = 0 ; ii < itemsinlist(pointlist) ; ii += 1)
			temp=stringfromlist(ii, pointlist)
			numtoremove = str2num(stringfromlist(ii, pointlist ,";"))
			if(!numtype(numtoremove) && strsearch(temp, "-", 0) == -1)
				deletepoints/M=0 numtoremove, 1, qq, RR,  EE,  dq, resolutionkernel
			else	
				sscanf temp, "%d-%d",lower,upper
				if(V_Flag!=2)
					print "ERROR parsing range of values to delete (delrefpoints)";abort
				endif
				if(upper<lower)
					numtoremove = lower
					lower=upper
					upper = numtoremove
				endif
				numtoremove = upper-lower+1
				deletepoints/M=0 lower, numtoremove, QQ, RR, EE, dq, resolutionkernel
			endif
		endfor
		
		hdf5savedata/z RR, fileID, "R"
		hdf5savedata/z QQ, fileID, "Q"
		hdf5savedata/z EE, fileID, "E"
		hdf5savedata/z dq, fileID, "dq"
		hdf5savedata/z resolutionkernel, fileID, "resolutionkernel"
		
	catch
		hdf5closefile/z fileID
		fileID=0
	endtry
	killwaves/z RR, qq, EE, dq, resolutionkernel
	
	print "NOW please remember to resplice individual angles (delRefpoints)"
	hdf5closefile/z fileID
End

Function/s buildsplicelist(start, ending)
	//build a list of consecutive filenames, in such a fashion that these consecutive files
	//can be spliced by the spliceFiles function.
	
	//e.g. buildsplicelist(13000, 13003)
	//returns:
	//  "PLP0013000;PLP0013001;PLP0013002;PLP0013003"
	variable start, ending
	string list = "", temp = ""
	variable ii
	for(ii = start ; ii < ending + 1 ; ii += 1)
		expandStrIntoPossibleFileName(num2istr(ii), temp)
		list += temp + ";"
	endfor
	return list
End

Function spliceFiles(outputPathStr, fname, filesToSplice, [factors, rebin])
	string outputPathStr, fname, filesToSplice, factors
	variable rebin
	//this function splices different reduced files together.
	
	string cDF = getdatafolder(1)
	string df = "root:packages:platypus:data:Reducer:"
	string qqStr="",RRstr="",dRStr="",dqStr="",filename,prefix=""
	string user = "", samplename = "", rednnote = ""
	
	variable fileID,ii,fileIDcomb, err=0, jj
	variable/c compSplicefactor

	try
		newdatafolder/o root:packages
		newdatafolder/o root:packages:platypus
		newdatafolder/o root:packages:platypus:data
		newdatafolder/o root:packages:platypus:data:reducer
		newdatafolder/o/s root:packages:platypus:data:reducer:temp
	 
		GetFileFolderInfo/q/z outputPathStr
		if(V_flag)//path doesn't exist
			print "ERROR please give valid path (spliceFiles)"
			return 1	
		endif
					
		//load in each of the files
		for(ii = 0 ; ii < itemsinlist(filesToSplice) ; ii += 1)
			hdf5openfile/R/z fileID as outputPathStr + stringfromlist(ii, filesToSplice) + ".h5"
			hdf5loaddata/z/o/q fileID, "R"
			Wave RR = $(stringfromlist(0, S_wavenames))
			
			hdf5loaddata/z/o/q fileID, "Q"
			Wave qq = $(stringfromlist(0, S_wavenames))
			
			hdf5loaddata/z/o/q fileID, "E"
			Wave EE = $(stringfromlist(0, S_wavenames))

			hdf5loaddata/z/o/q fileID, "dq"
			Wave dq = $(stringfromlist(0, S_wavenames))

			hdf5loaddata/z/o/q fileID, "resolutionkernel"
			if(!V_flag)
				Wave/z resolutionkernel = $(stringfromlist(0, S_wavenames))
			endif
					
			make/free/n=(numpnts(qq)) indx
			makeindex qq, indx
			
			if(waveexists(resolutionkernel))
				Pla_catalogue#MDindexsort(resolutionkernel, indx)
			endif
			sort qq, qq, RR, EE, dq
			
			if(ii == 0)
				make/o/d/n=(numpnts(qq)) tempQQ, tempRR, tempDR, tempDQ
				if(waveexists(resolutionkernel))
					duplicate/o resolutionkernel, tempResKernel
				endif
				Wave/z tempResKernel
							
				Wave tempQQ, tempRR, tempDR, tempDQ
				tempQQ = qq
				tempRR = RR
				tempDR = EE
				tempDQ = dq
				compsplicefactor = cmplx(1., 1.)

			else
				//splice with propagated error in the splice factor
				if(paramisdefault(factors))
					compSplicefactor = Pla_GetweightedScalingInoverlap(tempQQ, tempRR, tempDR, qq, RR, EE)		
				else
					if(itemsinlist(factors) <= ii)
						compSplicefactor = cmplx(str2num(stringfromlist(ii-1, factors)), 0)
					else
						compSplicefactor = Pla_GetweightedScalingInoverlap(tempQQ,tempRR, tempDR, qq, RR, EE)								
					endif
				endif
				if(numtype(REAL(compspliceFactor)))
					print "ERROR while splicing into combineddataset (spliceFiles)";abort
				endif
				
				print compSpliceFactor

				//possibly propagate error in scale factor.
				//EE = sqrt((real(compSplicefactor) * EE)^2 + (RR * imag(compSplicefactor))^2)
				EE *= real(compSplicefactor)
				RR *= real(compSplicefactor)
				
//2019.04.08 modification:
//delete 2 leading points of the curve with larger Q
//delete the datapoints with the larger %error from both curve
				print "start tempQQ n=",numpnts(tempQQ)," q=[",tempQQ[0],",",tempQQ[numpnts(tempQQ)-1],"]"
				print "start QQ n=",numpnts(QQ)," q=[",QQ[0],",",QQ[numpnts(QQ)-1],"]"

				make/N=(numpnts(tempQQ))/FREE tempDRoverRR
				tempDRoverRR = tempDR / tempRR
				
				deletepoints 0, 2, QQ, RR, DQ, EE
				make/N=(numpnts(QQ))/FREE EEoverRR
				EEoverRR = EE / RR
				
				make/N=(numpnts(tempQQ))/FREE temptempQQ
				make/N=(numpnts(tempQQ))/FREE temptempDR
				make/N=(numpnts(tempQQ))/FREE temptempDRoverRR
				temptempQQ = tempQQ
				temptempDR = tempDR
				temptempDRoverRR = tempDRoverRR
								
				for(jj = numpnts(tempQQ) - 1; jj >= 0; jj -= 1)
					if (tempQQ[jj] >= QQ[0] && tempQQ[jj] <= QQ[numpnts(QQ)-1])
						if(tempDRoverRR[jj] >= interp(tempQQ[jj], QQ, EEoverRR) || tempDR[jj] >= interp(tempQQ[jj], QQ, EE))
//							print "trim tempQQ n=",jj," q=",tempQQ[jj]," %tempDR=",tempDRoverRR[jj]," %EE=",interp(tempQQ[jj], QQ, EEoverRR)," delete tempQQ"
							deletepoints jj, 1, tempQQ, tempRR, tempDQ, tempDR, tempDRoverRR
							if(numpnts(tempQQ)==0)
								break
							endif
						else
							break
						endif
					endif
				endfor
				print "end tempQQ n=",numpnts(tempQQ)," q=[",tempQQ[0],",",tempQQ[numpnts(tempQQ)-1],"]"
				
				do
					if (QQ[0] >= tempQQ[0] && QQ[0] <= tempQQ[numpnts(tempQQ)-1])
						if(EEoverRR[0] >= interp(QQ[0], temptempQQ, temptempDRoverRR) || EE[0] >= interp(QQ[0], temptempQQ, temptempDR))
//							print "trim QQ n=",jj," q=",QQ[jj]," %EE=",EEoverRR[jj]," %tempDR=",interp(QQ[jj], temptempQQ, temptempDRoverRR)," delete QQ"
							deletepoints 0, 1, QQ, RR, DQ, EE, EEoverRR
							if(numpnts(QQ)==0)
								break
							endif
						else
							break
						endif
					else
						break;
					endif
				while(1)
				print "end QQ n=",numpnts(QQ),"q=[",QQ[0],",",QQ[numpnts(QQ)-1],"]"
//End 2019.04.12 modification
				
				concatenate/NP {RR}, tempRR
				concatenate/NP {QQ}, tempQQ
				concatenate/NP {DQ}, tempDQ
				concatenate/NP {EE}, tempDR
		
				if(waveexists(resolutionkernel))
					concatenate/NP=0 {resolutionkernel}, tempResKernel
					make/free/n=(numpnts(tempQQ)) indx
					makeindex tempQQ, indx
					Pla_catalogue#MDindexsort(tempResKernel, indx)
				endif
				
				sort tempQQ,tempQQ,tempRR,tempDR,tempDQ
				
//				for (jj=0;  jj<numpnts(tempQQ); jj+=1)
//					print "result Q=", tempQQ[jj],"R=",tempRR[jj],"dR=",tempDR[jj]
//				endfor
				
			endif
			
			killwaves/z qq, RR, EE, dq, resolutionkernel
			hdf5closefile/q fileID
			fileID=0
		endfor
		
//		if(!paramisdefault(rebin) && rebin > 0 && rebin < 15)
//			Pla_rebin_afterwards(tempQQ, tempRR, tempDR, tempDQ, rebin, tempQQ[0] - 0.00005, tempQQ[numpnts(tempQQ) - 1]+0.00005)
//			Wave W_Q_rebin, W_R_rebin, W_E_rebin, W_dq_rebin
//			duplicate/o W_Q_rebin, tempQQ
//			duplicate/o W_R_rebin, tempRR
//			duplicate/o W_E_rebin, tempDR
//			duplicate/o W_dq_rebin, tempDQ
//		endif
		
		newpath/z/o/q pla_temppath_write, outputpathStr
		open/P=PLA_temppath_write/z=1 fileIDcomb as  fname + ".dat"
		killpath/z pla_temppath_write

		if(V_flag)
			print "ERROR writing combined file (aplicefiles)";	 abort
		endif
		
		fprintf fileIDcomb, "Q (1/A)\t Ref\t dRef (SD)\t dq(FWHM, 1/A)\r"
		wfprintf fileIDcomb, "%g\t %g\t %g\t %g\r", tempQQ, tempRR, tempDR, tempDQ
		close fileIDcomb
		
		//now write a spliced XML file
		writeSpecRefXML1D(outputPathStr, fname, tempQQ, tempRR, tempDR, tempDQ, "", user, samplename, filestosplice, rednnote)
		
		//now write a spliced HDF file
		//but we can reduce the size of the resolution kernel to make the calculation MUCH faster.
		if(waveexists(resolutionkernel))
			reduceResolutionKernel(tempResKernel)
		endif
		writeSpecRefH5_1D(outputPathStr, fname, tempQQ, tempRR, tempdR, tempdQ, resolutionkernel = tempResKernel)
	catch
		if(fileID)
			hdf5closefile/z fileID
		endif
		err=1
	endtry
		if(fileID)
			hdf5closefile/z fileID
		endif
	setdatafolder $cDF
	killdatafolder/z  root:packages:platypus:data:reducer:temp
	return err
End

Function spliceFiles2(filesToSplice, [factors])
	string filesToSplice, factors
	//this function splices different reduced files together. but it doesn't rebin afterwards
	
	string cDF = getdatafolder(1)
	string df = "root:packages:platypus:data:Reducer:"
	
	variable fileID,ii,fileIDcomb, err=0, jj
	variable/c compSplicefactor

	try
		newdatafolder/o root:packages
		newdatafolder/o root:packages:platypus
		newdatafolder/o root:packages:platypus:data
		newdatafolder /o/s root:packages:platypus:data:reducer
	 
	 	make/o/n=0/d qq, rr, dr, dq, resolutionkernel
	 	
		//load in each of the files
		for(ii = 0 ; ii < itemsinlist(filesToSplice) ; ii += 1)
			print stringfromlist(ii, filesToSplice)
			Wave tq = $(df + stringfromlist(ii, filesToSplice) + ":qq")
			Wave tR = $(df + stringfromlist(ii, filesToSplice) + ":RR")
			Wave tdR= $(df + stringfromlist(ii, filesToSplice) + ":dR")
			Wave tdQ = $(df + stringfromlist(ii, filesToSplice) + ":dq")
			Wave trk = $(df + stringfromlist(ii, filesToSplice) + ":resolutionkernel")
			
			sort tq, tq, tR, tdR, tdQ
		 	Pla_catalogue#MDsort(trk, 0)
			
			if(ii == 0)
				redimension/n=(0, dimsize(trk, 1), dimsize(trk, 2)) resolutionkernel
				compsplicefactor = cmplx(1., 0.)			 
			else
				//splice with propagated error in the splice factor
				if(paramisdefault(factors))
					compSplicefactor = Pla_GetweightedScalingInoverlap(qq, rr, dR, tq, tr, tdr)		
				else
					if(itemsinlist(factors) <= ii)
						compSplicefactor = cmplx(str2num(stringfromlist(ii-1, factors)), 0)
					else
						compSplicefactor = Pla_GetweightedScalingInoverlap(qq, rr, dR, tq, tr, tdr)								
					endif
				endif
				if(numtype(REAL(compspliceFactor)))
					print "ERROR while splicing into combineddataset (spliceFiles)";abort
				endif
				
				print compSpliceFactor
			endif
			//think the following is wrong! No need to errors in quadrature if scalefactor does not depend on wavelength
			tdr = sqrt((real(compSplicefactor) * tdr)^2 + (tr * imag(compSplicefactor))^2)
			tr *= real(compSplicefactor)
			
			concatenate/NP {tr}, rr
			concatenate/NP {tq}, qq
			concatenate/NP { tdq}, dq
			concatenate/NP { tdr}, dr
			concatenate/NP=0 { trk}, resolutionkernel
			
			sort qq, qq, rr, dR, dq
			Pla_catalogue#MDsort(resolutionkernel, 0)
		endfor
	catch
	endtry
	setdatafolder $cDF
	return err
End

//Function Pla_splitfile(pathname, filename)
//	//split a single file with several frames into several files with 1 frame.
//	string pathname, filename
//	//splitfile("foobar:Users:anz:Desktop:test:","QKK0006492.nx.hdf")
//	variable ii,jj, kk, fileIDadd, fileIDcurrent, err=0, run_dims
//	string nodes = "",temp, addfile, cDF, nodename, attributes,filebase,filepath
//	
//	Struct HDF5DataInfo di
//	InitHDF5DataInfo(di)	// Initialize structure.
//
//	cDF = getdatafolder(1)
//	newdatafolder/o root:packages
//	newdatafolder/o root:packages:platypus
//	newdatafolder/o/s $"root:packages:platypus:temp"
//
//	newpath/o/q/z PATH_TO_DATA, pathname
//	pathinfo PATH_TO_DATA
//	filepath = S_path
//	if(!V_Flag)
//		print "ERROR while creating path (splitfile)"; abort
//	endif
//	//going to enumerate nodes that appear to grow with multiple frames.
//	//it's not clear from the file which ones do and which ones don't
//	nodes += "/entry1/data/hmm;"
//	nodes += "/entry1/data/run_number;"
//	
//	try
//		if(itemsinlist(filename)>1)
//			print "ERROR - do one file at a time (splitfile)";abort
//		endif
//		
//		filebase = removeending( stringfromlist(0,filename), ".nx.hdf")
//		temp = filebase +".nx.hdf"
//		
//		if(!doesnexusfileexist("PATH_TO_DATA", temp))
//			print "ERROR one of the filenames doesn't exist (splitfile)";abort	
//		endif
//		
//		//open the sourcefile as read-write
//		hdf5openfile/R/Z/P=PATH_TO_DATA fileIDcurrent as filename
//		if(V_Flag)
//			print "ERROR opening add file (splitfile)";abort
//		endif
//		
//		InitHDF5DataInfo(di)	// Initialize structure.
//		HDF5DatasetInfo(fileIDcurrent , "/entry1/data/hmm" , 0 , di ) 
//		run_dims = di.dims[0]
//
//		//now have to iterate through runnodes shrinking everything
//		for(ii = 0 ; ii < run_dims ; ii+=1)
//			print ii
//			//if its the first run copy the original file
//			//if it's subsequent just copy the 1st runnumber
//			if( ii == 0 )
//				copyfile/o filepath+filename as filepath+"temp.nx.hdf"
//				temp =  filepath+"temp.nx.hdf"
//				if(V_Flag)
//					print "ERROR copying file failed (splitfile)";abort
//				endif
//			else
//				copyfile/o filepath+filebase+"_0.nx.hdf" as filepath+filebase+"_"+num2istr(ii)+".nx.hdf"
//				temp =  filepath+filebase+"_"+num2istr(ii)+".nx.hdf"
//				if(V_Flag)
//					print "ERROR copying file failed (splitfile)";abort
//				endif				
//			endif
//			//open the datafile
//			hdf5openfile/Z fileIDadd as temp
//			if(V_Flag)
//				print "ERROR opening add file (splitfile)";abort
//			endif
//			
//			//now shrink the nodes
//			for(jj=0 ; jj<itemsinlist(nodes) ; jj+=1)
//				nodename = stringfromlist(jj, nodes)
////				print jj,nodename
//				if(ii==0)
//					attributes = saveAttributes(fileIDcurrent, nodename)
//				endif
//
//				HDF5DatasetInfo(fileIDcurrent ,  nodename , 0 , di ) 
//
//				//the runnumber is the first slab of the wave
//				make/o/i/n=(di.ndims, 4) hyperslab
//				hyperslab[][0] = 0
//				hyperslab[][1] = 1
//				hyperslab[][2] = 1
//				hyperslab[][3] = di.dims[p]
//				hyperslab[0][3] = 1
//				hyperslab[0][0] = ii
//					
//				hdf5loaddata/q/z/o/slab=hyperslab fileIDcurrent, nodename
//				if(V_Flag)
//					print "ERROR while loading a dataset (splitfile)";abort
//				endif
//				Wave numwave1 = $stringfromlist(0, S_Wavenames)			
//
//				if(ii==0)
//					hdf5savedata/z/o numwave1, fileIDadd, nodename
//					if(V_Flag)
//						print "ERROR couldn't save added data to ADD file (splitfile)";abort
//					endif
//					restoreAttributes(fileIDadd, nodename, attributes)
//				else
//					hyperslab[][0] = 0
//					hyperslab[][1] = 1
//					hyperslab[][2] = 1
//					hyperslab[][3] = dimsize(numwave1,p)
//					hdf5savedata/z/o/slab=hyperslab numwave1, fileIDadd, nodename
//					if(V_Flag)
//						print "ERROR couldn't save added data to ADD file (splitfile)";abort
//					endif
//				endif				
//				killwaves/a/z
//			endfor
//			hdf5closefile/z fileIDadd
//			if(V_Flag)
//				print "ERROR couldn't close split file (splitfile)";abort
//			endif
//			
//			if( ii == 0 )
//				//if you're the first runthrough repack the h5file, otherwise the file is still large
//				String unixCmd, igorCmd
//				unixCmd = "/usr/local/bin/h5repack -v -f GZIP=1 "+HFStoPosix("",filepath+"temp.nx.hdf",1,1)  + " " +HFStoPosix("",filepath,1,1)+filebase+"_"+num2istr(ii)+".nx.hdf"
//				sprintf igorCmd, "do shell script \"%s\"", unixCmd	
//				print igorCmd
//				ExecuteScriptText igorCmd
//			endif
//		endfor
//	
//		hdf5closefile/Z fileIDcurrent
//		if(V_Flag)
//			print "ERROR couldn't close current file (splitfile)";abort
//		endif
//	catch
//		err = 1
//		hdf5closefile/z fileIDadd
//		hdf5closefile/z fileIDcurrent
//	endtry
//
//	setdatafolder $cDF
//	killdatafolder/z $"root:packages:platypus:temp"
//	return err
//End
//
//Function/t saveAttributes(fileID, nodename)
////save the attributes of an HDF node in some waves
//	variable fileID
//	string nodename
//
//	variable ii
//	string wavenames = ""
//	HDF5ListAttributes/Z fileID , nodename
//
//	for(ii=0 ; ii<itemsinlist(S_HDF5ListAttributes) ; ii+=1)
//		HDF5loaddata/A=stringfromlist(ii, S_HDF5ListAttributes)/q/o/z fileID, nodename
//		wavenames +=  S_Wavenames
//	endfor
//
//	return wavenames
//End
//
//Function restoreAttributes(fileID, nodename, wavenames)
////restore the attributes of an HDF node from some waves
//	variable fileID
//	string nodename
//	string wavenames
//	variable ii
//
//	for(ii = 0 ; ii<itemsinlist(wavenames); ii+=1)
//		Wave/t/z textwav = $(stringfromlist(ii,wavenames))
//		if(waveexists(textwav))
//			hdf5savedata/A=nameofwave(textwav)/Z/o textwav, fileID, nodename	
//		endif
//		Wave/t/z wav = $(stringfromlist(ii,wavenames))
//		if(waveexists(wav))
//			hdf5savedata/A=nameofwave(wav)/Z/o wav, fileID, nodename	
//		endif
//	endfor
//End


//A wrapper script to reduce many X-ray files

Function reduceManyXrayFiles([attenuation])
	variable attenuation
	variable err, ii, jj, refnum
	string cDF = getdatafolder(1)
	string aFile, theFiles, base
	try
		Newdatafolder/o root:packages
		Newdatafolder /o/s root:packages:Xpert
		open/MULT=1/r/d/M="Please select all specular Xpert Pro files"/F="XRDML files:.xrdml;" refnum
		if(!strlen(S_filename))
			return 0
		endif
		theFiles = S_filename
		
		for(ii = 0 ; ii<itemsinlist(theFiles, "\r") ; ii+=1)
			aFile = Stringfromlist(ii, theFiles, "\r")
			print "reducing: ", aFile
			
			base = parsefilepath(3, aFile, ":", 0, 0)
			base = cleanupname(base, 0)
			
			do
				open/MULT=1/r/d/M="Please select up to two background runs for "+base/F="XRDML files:.xrdml;" refnum
				if(!strlen(S_filename))
					S_filename = ""
				endif
			while(itemsinlist(S_filename)>2)
		
			if(paramisdefault(attenuation))
				attenuation = 148
			endif
			//if there is no problem reducing it, then try to save it
			Pla_Xrayreduction#reduceXpertPro(afile, bkg1=stringfromlist(0, S_filename, "\r"), bkg2 = stringfromlist(1, S_filename, "\r"), attenuation=attenuation)
		endfor
	catch
		err = 1
	endtry

	setdatafolder $cDF
	return err
End

Function Pla_getVersion()
	string versionStr = "$Rev$"
	string template="$Rev"
	variable version
	sscanf versionStr, template+": %d $", version
	return version
End