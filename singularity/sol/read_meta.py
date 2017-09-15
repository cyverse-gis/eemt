#!/usr/bin/env python
import os
from subprocess import Popen, PIPE
from glob import glob
import sys
import decimal
import ConfigParser
from tiffparser import TiffParser
import math
import string
import tarfile
import re

def driver(): 
	"""
	Handles the execution of the program. Changes the working directory, un-archives all of the files in the directory, merges the partitioned TIFs into a single master TIF for each dataset, then converts the TIFs from their current projections to the projection defined by Daymet. 
	"""

	# Handle Arguments
	try:
		# Change to passed directory, if applicable
		if len(sys.argv) == 2:
			os.chdir(sys.argv[1])

		# Change to passed directory and test that na_dem exists
		elif len(sys.argv) == 3: 
			
			# Check to see if na_dem path is good
			if os.path.isfile(os.path.join(sys.argv[2], 'na_dem.tif')):
				daymet_path = os.path.join(os.getcwd(), sys.argv[2])
				os.chdir(sys.argv[1])
			else:
				print 'Location of na_dem.tif is invalid. Aborting.'
				sys.exit(1)

		# Otherwise
		else:
			print "Too many arguments passed."
			print "Usage: %s [directory]" % sys.argv[0]
			sys.exit(1)

	except OSError:
		print "Directory not found."
		print "Usage: %s [directory]" % sys.argv[0]
		sys.exit(1)

	input_path = os.getcwd()

	# Untar all of the files in the working directory before merging 
	# Then remove the old archives. 

	print '\nExtracting archived DEMs from Open Topography....\n'
	path = ['TWI.tar.gz', 'pitRemove.tar.gz']

	for archives in path:
		extract_dems(archives)
	
	print
	# Need to merge subfiles for each DEM output into a single TIFF
	# And remove the now unneeded partial DEMs

	# print 'Merging tiled DEMs...\n'

	# # D Infinity Catchment Area
	# print 'Merging catchment DEMs....'
	# path = os.path.join(os.getcwd(), "scap*.tif")
	# merge_files(glob(path), 'catch_total.tif')

	# print 'Merging flow DEMs....'
	# # D Infinity Flow 
	# path = os.path.join(os.getcwd(), "angp*.tif")
	# merge_files(glob(path), 'flow_total.tif')

	# print 'Merging slope DEMs....'
	# # D Infinity Slope
	# path = os.path.join(os.getcwd(), "slpp*.tif")
	# merge_files(glob(path), 'slope_total.tif')

	print 'Merging pit remove DEMs....'
	# Pit Remove 
	path = os.path.join(os.getcwd(), 'felp*.tif')
	merge_files(glob(path), 'pit.tif')

	print 'Merging TWI DEMs....'
	# Total Wetness Index
	path = os.path.join(os.getcwd(), 'twip*.tif')
	merge_files(glob(path), 'twi.tif')
	
	# Read the metadata to determine what projection to warp 
	# After reading, it will pass the projection info to convert_opentopo 
	# to update all of the available TIF files
	read_meta() 

	# Take the useful information out of the Daymet DEM

	# Update the current directory to include
	try:
		os.chdir(input_path)

	except OSError:
		print 'Unable to change to directory containing na_dem.tif. Aborting.'
		sys.exit(1)

	window_daymet(input_path)

	print 'Finished preparing raw inputs.\n'

# End driver() 

def extract_dems(archive):
	"""
	Extracts the specified archive file in the currrent directory. 
	"""
	
		# See if the file exists
	if os.path.exists(archive):

		# Check to see if the archive has already been extracted
		arch = tarfile.open(archive)
		for name in arch: 
			if os.path.exists(str(name.name)):
				print '\tContents of %s already extracted. Skipping.' % archive
				
				return

		# Archive not extracted yet
		else:
			print '\tExtracting %s. ' % archive

			# Setup the extract command with tar
			command = ['tar', 'zxf'] 
			command.append(archive)

			process = Popen (command, stdout=PIPE, shell=False)
			stdout, stderr = process.communicate()

			if process.returncode != 0: 
				print '\tErrors encountered extracting %s.\n' % archive
				print stderr
				sys.exit(1)

			# Successfully untarred/ungzipped specified archive
			else:
				print '\tFinished extracting contents of %s. ' % archive

		arch.close()

	# The file doesn't exist in the file system
	else:
		print '%s not found in the specified directory. Skipping.' % archive
		
# End extract_dems()

def merge_files(path, output): 
	"""
	Merges the filenames passed into a single TIFF file with gdalwarp. Assumes that the system running the application has at least 2 GB of available memory. Deletes the individual chunks of the file after creating the single combined TIFF. 
	"""

	if not os.path.exists(output):
		# Create the command to execute
		command = ['gdalwarp', '-overwrite'] 
		command.extend(path)
		command.append(output)

		# Execute the command
		process = Popen(command, stdout=PIPE, shell=False)
		stdout, stderr = process.communicate()

		if process.returncode != 0:
			print stderr
		else:
			print 'Finished merging %s.\n' % output

	else: 
		print '%s already merged. Skipping.\n' % output
		
# End merge_files()

def read_meta(dem):
	"""
	Uses gdalinfo output to determine the projection zone and region of the original data.
	Then passes this information to convert_opentopo() to convert the data to Daymet's projection.
	"""

	# Try opening the file and searching
	proj_info = dict()

	# Add the filenames to the end of the list
	command = ['gdalinfo', dem]

	# Execute the gdalwarp command
	process = Popen(command, stdout=PIPE, shell=False)

	# Check for errors
	stdout, stderr = process.communicate()

	if process.returncode != 0:
		print stderr
		print 'Failed to get original projection information from input data. Aborting'
		sys.exit(1)

	stdout = stdout.split('\n')

	for line in stdout:
		# Zone Information
		if line.startswith('PROJCS'):
			# Remove the punctation and break the individual words apart
			line = line.translate(None, ',[]"/')
			line = line.split()
			line = line[-1]
			# Remove the last character for North
			proj_info['zone'] = line[:-1]


		# Region Information
		elif line.startswith('    AUTHORITY'): 
			# Strip out the punctuation and split into space separated words
			line = ' '.join(re.split('[,"]', line))
			line = line.split()
			proj_info['region'] = line[-2]

	# Convert the DEMs to Daymet's projection
	print 'Converting OpenTopography DEMs to Daymet\'s projection.'
	convert_opentopo(proj_info)

	print 'Finished warping OpenTopography.\n' 

# End read_meta()



def convert_opentopo(proj_info):
	"""
	Creates another .tif file with the name .converted.tif for every .tif file located
	in the passed directory.The converted.tif file is supposed to be converted into the Daymet
	custom projection. Depends on theread_meta() method executing correctly. It doesn't check
	for the converted files before executing. Once the files are generated, script will call
	gdalinfo and try to parse the new coordinates from the output. The corner coordinates are
	returned in a list. Since everything is related to Daymet, it assumes the data is in the
	North and West hemispheres.
	"""

	# Command string to convert the DEM files from Open Topography to DAYMET's projection
	# Using the -tr command will lock the cell size: , '-tr', '10', '-10'
	# Right now I don't have a solution to importing the DEM's cell size here.
	# The resulting warp will alter the cell size and it will not be integer.

	command = ['gdalwarp', '-s_srs', 'EPSG:' + proj_info['region'], '-overwrite', '-t_srs',
			   "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs",
			   '-r', 'bilinear', '-of', 'GTiff']

	# Need to execute for each .tif file from OpenTopo
	path = ['pit.tif', 'twi.tif']

	for dem_file in path:

		# Create the output file name
		dem_output = dem_file[:-4] + '_c.tif'

		# Check to see if the file has already been created
		if not os.path.exists(dem_output):

			print "\tCreating %s." % dem_output

			# Add the filenames to the end of the list
			command.append(dem_file)
			command.append(dem_output)

			# Execute the gdalwarp command
			process = Popen(command, stdout=PIPE, shell=False)

			# Check for errors
			stdout, stderr = process.communicate()

			if process.returncode != 0:
				print stderr

			else:
				print '\tSuccessfully created %s.\n' % dem_output

			# Remove the filenames for next iteration
			command.remove(dem_file)
			command.remove(dem_output)

		# File already warped
		else:
			print '\t%s detected. Skipping.\n' % dem_output

# End convert_opentopo()
	
def window_daymet(output):
	"""
	Shrinks the Daymet DEM to include only relevant data to the Open
	Topography data set. 
	"""

	print 'Download and convert Daymet DEM.'
	# Parse dem file
	demParser = TiffParser()
	demParser.loadTiff(os.path.join(output,'pit_c.tif'))
    
    # get coordinates
	coords = demParser.getProjCoords()

	# Check for the Daymet DEM
	if not os.path.isfile('na_dem.tif'):
		# If it's not there, download it
		command = ['iget', '/iplant/home/tyson_swetnam/DAYMET/NA_DEM/na_dem.tif']
		process = Popen(command, stdout=PIPE, shell=False)

		print '\tDownloading Daymet DEM....'
		out, err = process.communicate()

		if process.returncode != 0:
			print 'Failed to download.\n'
			print err
			sys.exit(1)

		print '\tFinished downloading.\n'

	else:
		print '\tDaymet DEM detected. Processing.'

	# Round to the outside edges of overlapping Daymet tiles
	ul = [str(math.floor(decimal.Decimal(coords[1][0]) / 1000) * 1000), str(math.ceil(decimal.Decimal(coords[1][1]) / 1000) * 1000)]
	lr = [str(math.ceil(decimal.Decimal(coords[0][0]) / 1000) * 1000), str(math.floor(decimal.Decimal(coords[0][1]) / 1000) * 1000)]

	# Build command
	command = ['gdal_translate', '-projwin', ul[0], ul[1], lr[0], lr[1], 'na_dem.tif', os.path.join(output, 'na_dem.part.tif')]
        print ' '.join(command)
        print demParser.getProjCoords()
	print '\tPartitioning Daymet....'

	process = Popen(command, stdout=PIPE, shell=False)

	out, err = process.communicate()

	if process.returncode != 0:
		print 'Failed to partition Daymet DEM. \n'
		print err
		sys.exit(1)

	print 'Finished partitioning Daymet DEM as na_dem.part.tif.\n'

# End window_daymet()

if __name__ == '__main__':
	sys.exit(driver())
