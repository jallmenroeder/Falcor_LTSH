# LTSH Implementation in Falcor
## Linearly Transformed Spherical Harmonic (LTSH) expansions
This source code is the implementation of my bachelors thesis using LTSH for real-time polygonal area light shading.
It extends the existing technique of [Linearly Transformed Cosines (LTC) by Heitz et al.](https://eheitzresearch.wordpress.com/415-2/) to use more flexible spherical harmonic expansions instead of the clamped cosine function. This was possible because [Wang and Ramamoorthi derived a closed form expression of spherical harmonic expansions over polygonal domains](https://cseweb.ucsd.edu/~viscomp/projects/ash/).
You can find my [thesis](http://www.jallmenroeder.de/wp-content/uploads/2020/10/LTSH_BA_Thesis_final.pdf) and a [blog post](http://www.jallmenroeder.de/2020/11/19/linearly-transformed-spherical-harmonics/) about it online.

## Disclaimer
This code was written without the intention to publish it and to give me the results I needed for my thesis as fast as possible. There is obvious duplicate code and questionable design choices. However, instead of saying "I could improve it before publishing" and then never publishing it, I decided to just put it out here, as my solution relied heavily on other researchers making their code accessible. Please read the code with this desclaimer in mind. 
I'm very happy to answer any arising questions. Just mail me through contact∂jallmenroeder.de 

## Set Up
This project is not a standalone and needs to be integrated into the Falcor Framework (v. 3.2.1). See the [Falcor README](https://github.com/NVIDIAGameWorks/Falcor/tree/3.2.1#creating-a-new-project) for more information. I only tested the project using DirectX12.

## Credits
Thanks to Eric Heitz and his research team as well as Wang and Ramamoorthi for providing their code as I relied on their techniques and could reuse significant parts. 
A huge shoutout goes to my advisor Christoph Peters who put in a lot of time and expertise to help me with and review my work.
And thanks to NVIDIA for providing the [Falcor framework!](https://developer.nvidia.com/falcor)
You find the full list of references in my thesis (TODO: insert link).
