#pragma rtGlobals=1		// Use modern global access method.

constant NUMSTEPS = 35
constant DELRHO = 0.04
constant lambda = 10

Function Chebyshevapproximator(w, yy, xx): fitfunc
	Wave w, yy, xx

	Wave coef_forReflectivity = createCoefs_ForReflectivity(w)
	AbelesAll(coef_forReflectivity, yy, xx)
	yy = log(yy)
End

Function/wave createCoefs_ForReflectivity(w)
	wave w
	
	variable ii, xmod
	variable chebdegree = dimsize(w, 0) - 7
	variable lastz, lastSLD, numlayers = 0, thicknessoflastlayer=0, MAX_LENGTH

	MAX_LENGTH = w[6]

	make/d/free/n=(NUMSTEPS) chebSLD
	setscale/I x, 0, MAX_LENGTH, chebSLD

	for(ii = 0 ; ii < chebdegree ; ii+=1)
		multithread		chebSLD += calcCheb(w[ii + 7], MAX_LENGTH, ii,  x)
	endfor

	make/d/o/n=6 coef_forReflectivity = w
	lastz = -MAX_LENGTH/(NUMSTEPS - 1)
	lastSLD = w[2]
	numlayers = 0
	for(ii = 0 ; ii < dimsize(chebSLD, 0) ; ii+=1)
		if(abs(chebSLD[ii] - lastSLD) > delrho)
			redimension/n=(dimsize(coef_forReflectivity, 0) + 4) coef_forReflectivity
			coef_forReflectivity[4 * numlayers + 6] = MAX_LENGTH/(NUMSTEPS - 1)
			coef_forReflectivity[4 * numlayers + 7] = (chebSLD[ii])
			coef_forReflectivity[4 * numlayers + 8] = 0
			coef_forReflectivity[4 * numlayers + 9] = 0
			
			lastSLD = chebSLD[ii]
			numlayers += 1
			coef_forReflectivity[0] = numlayers
			thicknessoflastlayer = 0
		elseif(numlayers>0)
			coef_forReflectivity[4 * (numlayers - 1) + 6] += MAX_LENGTH/(NUMSTEPS - 1)
		endif
		lastz = pnt2x(chebsld, ii)
	endfor

	return coef_forReflectivity
End


Threadsafe Function calcCheb(coef, MAX_LENGTH, degree, x)
	variable coef, MAX_LENGTH, degree, x
	variable xmod
	xmod = 2 * (x/MAX_LENGTH) - 1
	return coef * chebyshev(degree, xmod) 
End

Function smoother(coefs, y_obs, y_calc, s_obs)
	Wave coefs, y_obs, y_calc, s_obs

	variable retval, betas = 0, ii
	
	make/n=(numpnts(y_obs))/free/d diff
	multithread diff = ((y_obs-y_calc)/s_obs)^2
	retval = sum(diff)
	
	Wave coef_forreflectivity = createCoefs_ForReflectivity(coefs)
	for(ii = 0 ; ii < coef_forreflectivity[0] + 1 ; ii+=1)
		if(ii == 0)
			betas += (coef_forreflectivity[2] - coef_forreflectivity[7])^2
		elseif(ii == coef_forreflectivity[0])
			betas += (coef_forreflectivity[3] - coef_forreflectivity[(4 * (ii - 1)) + 7])^2
		else
			betas += (coef_forreflectivity[4 * (ii-1) + 7] - coef_forreflectivity[4 * ii  + 7])^2
		endif
	endfor	

	return retval + lambda * betas
end